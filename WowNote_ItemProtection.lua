-- WowNote_ItemProtection.lua
-- Protect important set/items from WowNote auto-sell, auto-roll disenchant/greed and accidental delete/vendor actions.

local MODULE_NAME = "WowNote Item Protection"

local frame
local statusText
local listEdit
local manualBlockCheck
local captureProtectedItem = false
local protectedCursorItem
local wrappersInstalled = false
local merchantProtectedButtons = {}
local PROTECTED_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local textAreaCounter = 0
local activeTextArea
local SetListEditTextSafe
local linkHookInstalled = false
local bagTooltipHookInstalled = false
local itemProtectionEventFrame
local merchantEventFrame
local merchantButtonTimerFrame
local buybackTimerFrame
local buybackGuardRunning = false
local lastBuybackProtectedLink
local pendingBuybackCheck
local pendingMerchantButtonUpdate
local pendingMerchantButtonUpdateDelay = 0.12
local lastBuybackCheckAt = 0
local UpdateMerchantProtectedButtons
local QueueMerchantButtonUpdate
local QueueBuybackGuard
local SetStatus
local SyncProtectionBackup
local MigrateProtectionStorage
local EnsureStandaloneStores
local CountProtectedLines
local RecoverProtectionFromAllStores
local GetCharacterKey
local GetBagSlotFromButton
local editDirty = false
local suppressEditDirty = false
local manualBlockDirty = false
local lastProtectedVendorAttemptAt = 0

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote:|r " .. tostring(msg)) end
end

local function Trim(text)
    text = text or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function Lower(text)
    return string.lower(Trim(text or ""))
end

local function IsListEmpty(text)
    return Trim(text or "") == ""
end

local function IsProtectionClearMarkerSet(store)
    return type(store) == "table" and store.protectionListCleared == true
end

local function SetProtectionClearMarker(store, cleared)
    if type(store) ~= "table" then return end
    store.protectionListCleared = cleared and true or false
    store.protectionListClearedAt = (cleared and time and time()) or nil
end

local function SetProtectionClearMarkerAll(db, cleared)
    local key = GetCharacterKey()
    SetProtectionClearMarker(db, cleared)
    SetProtectionClearMarker(WowNoteItemProtectionCharDB, cleared)
    SetProtectionClearMarker(WowNoteCharDB, cleared)
    if type(WowNoteCharDB) == "table" then SetProtectionClearMarker(WowNoteCharDB.itemProtection, cleared) end
    SetProtectionClearMarker(WowNoteDB, cleared)
    if type(WowNoteDB) == "table" then
        SetProtectionClearMarker(WowNoteDB.itemProtection, cleared)
        if type(WowNoteDB.itemProtection) == "table" and type(WowNoteDB.itemProtection.characters) == "table" and key ~= "UNKNOWN" then
            SetProtectionClearMarker(WowNoteDB.itemProtection.characters[key], cleared)
        end
        if type(WowNoteDB.itemProtectionBackups) == "table" and key ~= "UNKNOWN" then
            SetProtectionClearMarker(WowNoteDB.itemProtectionBackups[key], cleared)
        end
    end
    SetProtectionClearMarker(WowNoteItemProtectionDB, cleared)
    if type(WowNoteItemProtectionDB) == "table" and type(WowNoteItemProtectionDB.characters) == "table" and key ~= "UNKNOWN" then
        SetProtectionClearMarker(WowNoteItemProtectionDB.characters[key], cleared)
    end
end

local function IsProtectionAuthoritativeSet(store)
    return type(store) == "table" and store.protectionListAuthoritative == true
end

local function SetProtectionAuthoritativeMarker(store, authoritative)
    if type(store) ~= "table" then return end
    store.protectionListAuthoritative = authoritative and true or false
    store.protectionListAuthoritativeAt = (authoritative and time and time()) or store.protectionListAuthoritativeAt
end

local function SetProtectionAuthoritativeMarkerAll(db, authoritative)
    local key = GetCharacterKey()
    SetProtectionAuthoritativeMarker(db, authoritative)
    SetProtectionAuthoritativeMarker(WowNoteItemProtectionCharDB, authoritative)
    SetProtectionAuthoritativeMarker(WowNoteCharDB, authoritative)
    if type(WowNoteCharDB) == "table" then SetProtectionAuthoritativeMarker(WowNoteCharDB.itemProtection, authoritative) end
    SetProtectionAuthoritativeMarker(WowNoteDB, authoritative)
    if type(WowNoteDB) == "table" then
        SetProtectionAuthoritativeMarker(WowNoteDB.itemProtection, authoritative)
        if type(WowNoteDB.itemProtection) == "table" and type(WowNoteDB.itemProtection.characters) == "table" and key ~= "UNKNOWN" then
            SetProtectionAuthoritativeMarker(WowNoteDB.itemProtection.characters[key], authoritative)
        end
        if type(WowNoteDB.itemProtectionBackups) == "table" and key ~= "UNKNOWN" then
            SetProtectionAuthoritativeMarker(WowNoteDB.itemProtectionBackups[key], authoritative)
        end
    end
    SetProtectionAuthoritativeMarker(WowNoteItemProtectionDB, authoritative)
    if type(WowNoteItemProtectionDB) == "table" and type(WowNoteItemProtectionDB.characters) == "table" and key ~= "UNKNOWN" then
        SetProtectionAuthoritativeMarker(WowNoteItemProtectionDB.characters[key], authoritative)
    end
end

local function IsRecoverySuppressed(db)
    return IsProtectionClearMarkerSet(db)
        or IsProtectionClearMarkerSet(WowNoteItemProtectionCharDB)
        or IsProtectionAuthoritativeSet(db)
        or IsProtectionAuthoritativeSet(WowNoteItemProtectionCharDB)
end

GetCharacterKey = function()
    local name = UnitName and UnitName("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    name = Trim(name or "")
    realm = Trim(realm or "")
    if name == "" or name == "Unknown" or name == UNKNOWNOBJECT then
        return "UNKNOWN"
    end
    if realm == "" then realm = "UnknownRealm" end
    return realm .. "::" .. name
end

local function EnsureProtectionBackupStore()
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.itemProtectionBackups) ~= "table" then WowNoteDB.itemProtectionBackups = {} end
    return WowNoteDB.itemProtectionBackups
end

EnsureStandaloneStores = function()
    -- Standalone SavedVariables. These are declared directly in the TOC so Item
    -- Protection does not depend on the larger WowNoteDB/WowNoteCharDB init path.
    if type(WowNoteItemProtectionCharDB) ~= "table" then WowNoteItemProtectionCharDB = {} end
    if type(WowNoteItemProtectionDB) ~= "table" then WowNoteItemProtectionDB = {} end
    if type(WowNoteItemProtectionDB.characters) ~= "table" then WowNoteItemProtectionDB.characters = {} end

    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end

    local key = GetCharacterKey()
    if key ~= "UNKNOWN" and type(WowNoteItemProtectionDB.characters[key]) ~= "table" then
        WowNoteItemProtectionDB.characters[key] = {}
    end

    return WowNoteItemProtectionCharDB, WowNoteItemProtectionDB, key
end

local function ExtractItemId(itemLink)
    if not itemLink then return nil end
    return tonumber(string.match(tostring(itemLink), "item:(%d+):")) or tonumber(tostring(itemLink))
end

local function ExtractBracketName(text)
    if not text then return nil end
    return string.match(tostring(text), "%[(.-)%]")
end

local function GetItemNameFromLinkOrId(entry)
    local link = tostring(entry or "")
    if link == "" then return nil end
    if GetItemInfo then
        local id = ExtractItemId(link) or tonumber(link)
        if id then
            local name, itemLink = GetItemInfo(id)
            return name, itemLink
        end
        local name, itemLink = GetItemInfo(link)
        return name, itemLink
    end
    return ExtractBracketName(link)
end

local function EnsureDB(skipRecover)
    local charStore, accountStore, key = EnsureStandaloneStores()
    local db = charStore

    if db.protectedItems == nil then db.protectedItems = "" end

    -- Keep the old nested location populated for compatibility with older helper
    -- code, but the authoritative per-character store is now the standalone
    -- WowNoteItemProtectionCharDB table declared in the TOC.
    if type(WowNoteCharDB.itemProtection) ~= "table" then WowNoteCharDB.itemProtection = {} end

    if MigrateProtectionStorage then MigrateProtectionStorage(db) end
    if not skipRecover and RecoverProtectionFromAllStores then RecoverProtectionFromAllStores(db, false) end
    if db.blockManual == nil then
        db.blockManual = (db.blockManualDelete ~= false and db.blockManualVendor ~= false)
    end
    db.blockManualDelete = db.blockManual ~= false
    db.blockManualVendor = db.blockManual ~= false
    return db
end

local function GetEntryKey(entry)
    local id = ExtractItemId(entry) or tonumber(Trim(entry or ""))
    if id then return string.format("id:%010d", id) end
    local bracket = ExtractBracketName(entry)
    if bracket and bracket ~= "" then return Lower(bracket) end
    return Lower(entry)
end

local function NormalizeListText(listText)
    local seen = {}
    local entries = {}
    for rawLine in string.gmatch((listText or "") .. "\n", "(.-)\n") do
        local entry = Trim(rawLine)
        entry = string.gsub(entry, "^%-+%s*", "")
        if entry ~= "" then
            local key = GetEntryKey(entry)
            if key ~= "" and not seen[key] then
                seen[key] = true
                table.insert(entries, entry)
            end
        end
    end
    table.sort(entries, function(a, b) return GetEntryKey(a) < GetEntryKey(b) end)
    return table.concat(entries, "\n")
end

SyncProtectionBackup = function(db)
    if type(db) ~= "table" then return end
    local protectedItems = NormalizeListText(db.protectedItems or "")
    db.protectedItems = protectedItems
    local cleared = IsListEmpty(protectedItems) and db.protectionListCleared == true

    local charStore, accountStore, key = EnsureStandaloneStores()

    -- Primary standalone SavedVariables.
    charStore.protectedItems = protectedItems
    SetProtectionClearMarker(charStore, cleared)
    SetProtectionAuthoritativeMarker(charStore, db.protectionListAuthoritative == true)
    charStore.blockManual = db.blockManual ~= false
    charStore.blockManualDelete = db.blockManual ~= false
    charStore.blockManualVendor = db.blockManual ~= false
    charStore.updatedAt = time and time() or nil

    -- Direct account/global storage inside the already proven WowNoteDB path.
    -- This is intentionally redundant: Item Protection must survive even if a
    -- realm/character key is resolved differently on one login.
    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.itemProtection) ~= "table" then WowNoteDB.itemProtection = {} end
    WowNoteDB.itemProtection.protectedItems = protectedItems
    SetProtectionClearMarker(WowNoteDB.itemProtection, cleared)
    SetProtectionAuthoritativeMarker(WowNoteDB.itemProtection, db.protectionListAuthoritative == true)
    WowNoteDB.itemProtection.blockManual = db.blockManual ~= false
    WowNoteDB.itemProtection.blockManualDelete = db.blockManual ~= false
    WowNoteDB.itemProtection.blockManualVendor = db.blockManual ~= false
    WowNoteDB.itemProtection.updatedAt = time and time() or nil

    -- Account-level character backup, keyed by realm::character.
    if key ~= "UNKNOWN" then
        if type(accountStore.characters[key]) ~= "table" then accountStore.characters[key] = {} end
        accountStore.characters[key].protectedItems = protectedItems
        SetProtectionClearMarker(accountStore.characters[key], cleared)
        SetProtectionAuthoritativeMarker(accountStore.characters[key], db.protectionListAuthoritative == true)
        accountStore.characters[key].blockManual = db.blockManual ~= false
        accountStore.characters[key].blockManualDelete = db.blockManual ~= false
        accountStore.characters[key].blockManualVendor = db.blockManual ~= false
        accountStore.characters[key].updatedAt = time and time() or nil

        if type(WowNoteDB.itemProtection.characters) ~= "table" then WowNoteDB.itemProtection.characters = {} end
        if type(WowNoteDB.itemProtection.characters[key]) ~= "table" then WowNoteDB.itemProtection.characters[key] = {} end
        WowNoteDB.itemProtection.characters[key].protectedItems = protectedItems
        SetProtectionClearMarker(WowNoteDB.itemProtection.characters[key], cleared)
        SetProtectionAuthoritativeMarker(WowNoteDB.itemProtection.characters[key], db.protectionListAuthoritative == true)
        WowNoteDB.itemProtection.characters[key].blockManual = db.blockManual ~= false
        WowNoteDB.itemProtection.characters[key].blockManualDelete = db.blockManual ~= false
        WowNoteDB.itemProtection.characters[key].blockManualVendor = db.blockManual ~= false
        WowNoteDB.itemProtection.characters[key].updatedAt = time and time() or nil
    end

    -- Legacy mirrors for older code/builds and migration from broken versions.
    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.itemProtection) ~= "table" then WowNoteCharDB.itemProtection = {} end
    WowNoteCharDB.itemProtection.protectedItems = protectedItems
    SetProtectionClearMarker(WowNoteCharDB.itemProtection, cleared)
    SetProtectionAuthoritativeMarker(WowNoteCharDB.itemProtection, db.protectionListAuthoritative == true)
    WowNoteCharDB.itemProtection.blockManual = db.blockManual ~= false
    WowNoteCharDB.itemProtection.blockManualDelete = db.blockManual ~= false
    WowNoteCharDB.itemProtection.blockManualVendor = db.blockManual ~= false

    if key ~= "UNKNOWN" then
        local store = EnsureProtectionBackupStore()
        if type(store[key]) ~= "table" then store[key] = {} end
        store[key].protectedItems = protectedItems
        SetProtectionClearMarker(store[key], cleared)
        SetProtectionAuthoritativeMarker(store[key], db.protectionListAuthoritative == true)
        store[key].blockManual = db.blockManual ~= false
        store[key].blockManualDelete = db.blockManual ~= false
        store[key].blockManualVendor = db.blockManual ~= false
        store[key].updatedAt = time and time() or nil
    end
end

MigrateProtectionStorage = function(db)
    if type(db) ~= "table" or db._migrationRunning then return end
    db._migrationRunning = true

    if IsRecoverySuppressed(db) then
        db.protectedItems = NormalizeListText(db.protectedItems or "")
        db._migrationRunning = nil
        return
    end

    local candidates = {}
    local function AddCandidate(value)
        if type(value) == "string" and not IsListEmpty(value) then
            table.insert(candidates, value)
        end
    end
    local function CopyFlags(source)
        if type(source) ~= "table" then return end
        -- blockManual is the authoritative single setting from v1.15.27 onward.
        -- Older dual keys are only used when that single setting is absent.
        if db.blockManual == nil and source.blockManual ~= nil then
            db.blockManual = source.blockManual ~= false
        end
        if db.blockManual == nil and (source.blockManualDelete ~= nil or source.blockManualVendor ~= nil) then
            db.blockManual = (source.blockManualDelete ~= false and source.blockManualVendor ~= false)
        end
        if db.blockManualDelete == nil and source.blockManualDelete ~= nil then
            db.blockManualDelete = source.blockManualDelete ~= false
        end
        if db.blockManualVendor == nil and source.blockManualVendor ~= nil then
            db.blockManualVendor = source.blockManualVendor ~= false
        end
        if db.protectionListAuthoritative ~= true and source.protectionListAuthoritative == true then
            db.protectionListAuthoritative = true
        end
    end

    local key = GetCharacterKey()
    AddCandidate(db.protectedItems)

    if type(WowNoteItemProtectionCharDB) == "table" then
        AddCandidate(WowNoteItemProtectionCharDB.protectedItems)
        CopyFlags(WowNoteItemProtectionCharDB)
    end

    if type(WowNoteItemProtectionDB) == "table" then
        if key ~= "UNKNOWN" and type(WowNoteItemProtectionDB.characters) == "table" and type(WowNoteItemProtectionDB.characters[key]) == "table" then
            AddCandidate(WowNoteItemProtectionDB.characters[key].protectedItems)
            CopyFlags(WowNoteItemProtectionDB.characters[key])
        end
    end

    if type(WowNoteCharDB) == "table" then
        AddCandidate(WowNoteCharDB.protectedItems)
        if type(WowNoteCharDB.itemProtection) == "table" then
            AddCandidate(WowNoteCharDB.itemProtection.protectedItems)
            CopyFlags(WowNoteCharDB.itemProtection)
        end
    end

    if type(WowNoteDB) == "table" then
        if type(WowNoteDB.itemProtection) == "table" then
            -- v1.15.15 authoritative global fallback.
            AddCandidate(WowNoteDB.itemProtection.protectedItems)
            CopyFlags(WowNoteDB.itemProtection)
            if key ~= "UNKNOWN" and type(WowNoteDB.itemProtection.characters) == "table" and type(WowNoteDB.itemProtection.characters[key]) == "table" then
                AddCandidate(WowNoteDB.itemProtection.characters[key].protectedItems)
                CopyFlags(WowNoteDB.itemProtection.characters[key])
            end
        elseif type(WowNoteDB.itemProtection) == "string" then
            AddCandidate(WowNoteDB.itemProtection)
        end
        AddCandidate(WowNoteDB.protectedItems)
        local backups = WowNoteDB.itemProtectionBackups
        if key ~= "UNKNOWN" and type(backups) == "table" and type(backups[key]) == "table" then
            AddCandidate(backups[key].protectedItems)
            CopyFlags(backups[key])
        end
    end

    if #candidates > 0 then
        db.protectedItems = NormalizeListText(table.concat(candidates, "\n"))
    else
        db.protectedItems = NormalizeListText(db.protectedItems or "")
    end

    if db.blockManual == nil then
        db.blockManual = (db.blockManualDelete ~= false and db.blockManualVendor ~= false)
    end
    db.blockManualDelete = db.blockManual ~= false
    db.blockManualVendor = db.blockManual ~= false

    db._migrationRunning = nil
    -- Always sync, even if the list is empty, so every store has the same shape
    -- and the debug command can verify that the variables are present.
    if SyncProtectionBackup then SyncProtectionBackup(db) end
end

CountProtectedLines = function(text)
    local count = 0
    for rawLine in string.gmatch((text or "") .. "\n", "(.-)\n") do
        if Trim(rawLine) ~= "" then count = count + 1 end
    end
    return count
end


RecoverProtectionFromAllStores = function(db, force)
    db = db or EnsureDB()
    if type(db) ~= "table" or db._recoverRunning then return db and db.protectedItems or "" end
    db._recoverRunning = true

    if IsRecoverySuppressed(db) then
        db.protectedItems = NormalizeListText(db.protectedItems or "")
        db._recoverRunning = nil
        return db.protectedItems or ""
    end

    local key = GetCharacterKey()
    local candidates = {}
    local function AddCandidate(value)
        if type(value) == "string" and not IsListEmpty(value) then
            table.insert(candidates, value)
        end
    end
    local function RecoverFlags(source)
        if type(source) ~= "table" then return end
        -- Only recover when the authoritative per-character DB has no explicit
        -- value yet. Explicit false must survive reloads and backup syncs.
        if db.blockManual == nil and source.blockManual ~= nil then
            db.blockManual = source.blockManual ~= false
        end
        if db.blockManual == nil and (source.blockManualDelete ~= nil or source.blockManualVendor ~= nil) then
            db.blockManual = (source.blockManualDelete ~= false and source.blockManualVendor ~= false)
        end
        if db.blockManualDelete == nil and source.blockManualDelete ~= nil then
            db.blockManualDelete = source.blockManualDelete ~= false
        end
        if db.blockManualVendor == nil and source.blockManualVendor ~= nil then
            db.blockManualVendor = source.blockManualVendor ~= false
        end
        if db.protectionListAuthoritative ~= true and source.protectionListAuthoritative == true then
            db.protectionListAuthoritative = true
        end
    end

    AddCandidate(db.protectedItems)
    RecoverFlags(db)

    if type(WowNoteItemProtectionCharDB) == "table" then
        AddCandidate(WowNoteItemProtectionCharDB.protectedItems)
        RecoverFlags(WowNoteItemProtectionCharDB)
    end
    if type(WowNoteItemProtectionDB) == "table" and type(WowNoteItemProtectionDB.characters) == "table" and key ~= "UNKNOWN" then
        local accountChar = WowNoteItemProtectionDB.characters[key]
        if type(accountChar) == "table" then
            AddCandidate(accountChar.protectedItems)
            RecoverFlags(accountChar)
        end
    end
    if type(WowNoteCharDB) == "table" then
        AddCandidate(WowNoteCharDB.protectedItems)
        RecoverFlags(WowNoteCharDB)
        if type(WowNoteCharDB.itemProtection) == "table" then
            AddCandidate(WowNoteCharDB.itemProtection.protectedItems)
            RecoverFlags(WowNoteCharDB.itemProtection)
        end
    end
    if type(WowNoteDB) == "table" then
        if type(WowNoteDB.itemProtection) == "table" then
            AddCandidate(WowNoteDB.itemProtection.protectedItems)
            RecoverFlags(WowNoteDB.itemProtection)
            if type(WowNoteDB.itemProtection.characters) == "table" and key ~= "UNKNOWN" then
                local globalChar = WowNoteDB.itemProtection.characters[key]
                if type(globalChar) == "table" then
                    AddCandidate(globalChar.protectedItems)
                    RecoverFlags(globalChar)
                end
            end
        elseif type(WowNoteDB.itemProtection) == "string" then
            AddCandidate(WowNoteDB.itemProtection)
        end
        AddCandidate(WowNoteDB.protectedItems)
        RecoverFlags(WowNoteDB)
        if type(WowNoteDB.itemProtectionBackups) == "table" and key ~= "UNKNOWN" then
            local legacyAccount = WowNoteDB.itemProtectionBackups[key]
            if type(legacyAccount) == "table" then
                AddCandidate(legacyAccount.protectedItems)
                RecoverFlags(legacyAccount)
            end
        end
    end

    local recovered = ""
    if #candidates > 0 then
        recovered = NormalizeListText(table.concat(candidates, "\n"))
    else
        recovered = NormalizeListText(db.protectedItems or "")
    end

    local currentCount = CountProtectedLines(db.protectedItems or "")
    local recoveredCount = CountProtectedLines(recovered or "")
    if force or recoveredCount > currentCount or IsListEmpty(db.protectedItems or "") then
        db.protectedItems = recovered
        if SyncProtectionBackup then SyncProtectionBackup(db) end
    end

    db._recoverRunning = nil
    return db.protectedItems or ""
end


local function RemoveEntryKeyFromListText(listText, removeKey)
    local kept = {}
    local removed = false
    for rawLine in string.gmatch((listText or "") .. "\n", "(.-)\n") do
        local line = Trim(rawLine)
        if line ~= "" then
            if GetEntryKey(line) == removeKey then
                removed = true
            else
                table.insert(kept, line)
            end
        end
    end
    return NormalizeListText(table.concat(kept, "\n")), removed
end

local function PurgeProtectionEntryFromAllStores(removeKey)
    if not removeKey or removeKey == "" then return end
    local function PurgeStore(store)
        if type(store) ~= "table" then return end
        if type(store.protectedItems) == "string" then
            local updated = RemoveEntryKeyFromListText(store.protectedItems, removeKey)
            store.protectedItems = updated
        end
    end
    local key = GetCharacterKey()

    PurgeStore(WowNoteItemProtectionCharDB)
    PurgeStore(WowNoteCharDB)
    if type(WowNoteCharDB) == "table" then PurgeStore(WowNoteCharDB.itemProtection) end
    PurgeStore(WowNoteDB)
    if type(WowNoteDB) == "table" then
        PurgeStore(WowNoteDB.itemProtection)
        if type(WowNoteDB.itemProtection) == "table" and type(WowNoteDB.itemProtection.characters) == "table" and key ~= "UNKNOWN" then
            PurgeStore(WowNoteDB.itemProtection.characters[key])
        end
        if type(WowNoteDB.itemProtectionBackups) == "table" and key ~= "UNKNOWN" then
            PurgeStore(WowNoteDB.itemProtectionBackups[key])
        end
    end
    if type(WowNoteItemProtectionDB) == "table" then
        PurgeStore(WowNoteItemProtectionDB)
        if type(WowNoteItemProtectionDB.characters) == "table" and key ~= "UNKNOWN" then
            PurgeStore(WowNoteItemProtectionDB.characters[key])
        end
    end
end

local function BuildListIndex(listText)
    local names = {}
    local ids = {}
    for rawLine in string.gmatch((listText or "") .. "\n", "(.-)\n") do
        local entry = Trim(rawLine)
        entry = string.gsub(entry, "^%-+%s*", "")
        if entry ~= "" then
            local id = ExtractItemId(entry) or tonumber(entry)
            if id then ids[id] = true end
            local bracketName = ExtractBracketName(entry)
            if bracketName and bracketName ~= "" then
                names[Lower(bracketName)] = true
            elseif not id then
                names[Lower(entry)] = true
            end
        end
    end
    return names, ids
end

local function LinkOrEntryForBagSlot(bag, slot)
    if not bag or not slot or not GetContainerItemLink then return nil end
    local link = GetContainerItemLink(bag, slot)
    if link then return link end
    return nil
end

local function GetCursorItemLinkOrId()
    if GetCursorInfo then
        local kind, itemID, itemLink = GetCursorInfo()
        if kind == "item" then
            return itemLink or itemID
        end
    end
    if protectedCursorItem then return protectedCursorItem.link or protectedCursorItem.id or protectedCursorItem.name end
    return nil
end

local function MatchesProtected(entry)
    local db = EnsureDB()
    local list = db.protectedItems or ""
    if Trim(list) == "" then return false end
    local names, ids = BuildListIndex(list)
    local id = ExtractItemId(entry) or tonumber(Trim(entry or ""))
    if id and ids[id] then return true, id end
    local name = ExtractBracketName(entry)
    if not name or name == "" then
        name = GetItemNameFromLinkOrId(entry)
    end
    name = Lower(name)
    if name ~= "" and names[name] then return true, name end
    return false
end

function WowNote_IsItemProtected(entry)
    local protected = MatchesProtected(entry)
    return protected == true
end

local function AddEntry(entry, silent)
    entry = Trim(entry or "")
    if entry == "" then return false end
    if MatchesProtected(entry) then
        if listEdit then listEdit:SetText(EnsureDB().protectedItems or "") end
        if not silent then Print("Item is already protected: " .. tostring(entry)) end
        return true
    end
    local db = EnsureDB()
    local current = Trim(db.protectedItems or "")
    if current ~= "" then current = current .. "\n" .. entry else current = entry end
    db.protectedItems = NormalizeListText(current)
    SetProtectionClearMarkerAll(db, false)
    SetProtectionAuthoritativeMarkerAll(db, true)
    if SyncProtectionBackup then SyncProtectionBackup(db) end
    if listEdit then listEdit:SetText(db.protectedItems or "") end
    if not silent then Print("Protected item added: " .. tostring(entry)) end
    return true
end

function WowNote_AddProtectedItem(entry)
    return AddEntry(entry, false)
end


function WowNote_QuickAddCursorItemToProtection()
    local entry
    if GetCursorInfo then
        local kind, itemID, itemLink = GetCursorInfo()
        if kind == "item" then
            entry = itemLink or itemID
        end
    end
    entry = entry or GetCursorItemLinkOrId()
    if entry then
        local ok = AddEntry(tostring(entry), false)
        if ok and ClearCursor then ClearCursor() end
        return ok
    end
    captureProtectedItem = true
    return false
end

local function QuickProtectBagButton(button)
    if type(button) ~= "table" then return end
    if not (captureProtectedItem or (IsAltKeyDown and IsAltKeyDown() and IsShiftKeyDown and IsShiftKeyDown())) then return end
    local bag, slot = GetBagSlotFromButton(button)
    local link = LinkOrEntryForBagSlot(bag, slot)
    if link then
        AddEntry(link, false)
        captureProtectedItem = false
        SetStatus("Protected bag item: " .. tostring(link))
    end
end

local function RemoveEntry(entry)
    entry = Trim(entry or "")
    if entry == "" then return false end
    local removeKey = GetEntryKey(entry)
    local db = EnsureDB(true)
    local updated, removed = RemoveEntryKeyFromListText(db.protectedItems or "", removeKey)
    db.protectedItems = updated
    SetProtectionClearMarkerAll(db, IsListEmpty(updated))
    SetProtectionAuthoritativeMarkerAll(db, true)
    PurgeProtectionEntryFromAllStores(removeKey)
    if SyncProtectionBackup then SyncProtectionBackup(db) end
    if listEdit and SetListEditTextSafe then SetListEditTextSafe(db.protectedItems or "") elseif listEdit then listEdit:SetText(db.protectedItems or "") end
    editDirty = false
    return removed
end

SetStatus = function(text)
    if statusText then statusText:SetText(text or "") end
end

local function BlockedMessage(action, item)
    Print("Blocked " .. tostring(action) .. " for protected item " .. tostring(item or "") .. ". Remove it from Item Protection first.")
end

local function IsMerchantWindowOpen()
    return MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
end

local function GetProtectedBagSlotLink(bag, slot)
    if not bag or not slot or not GetContainerItemLink then return nil end
    local link = GetContainerItemLink(bag, slot)
    if link and WowNote_IsItemProtected and WowNote_IsItemProtected(link) then return link end
    return nil
end

function WowNote_IsBagSlotProtected(bag, slot)
    return GetProtectedBagSlotLink(bag, slot) ~= nil
end

function WowNote_ItemProtection_HandleBagClick(button)
    return false
end

function WowNote_ItemProtection_HandleBagModifiedClick(button, mouseButton)
    return false
end

local function IsCallable(value)
    return type(value) == "function"
end

local function SafeCallMethod(object, methodName)
    if type(object) ~= "table" then return nil end
    local method = object[methodName]
    if not IsCallable(method) then return nil end
    return method(object)
end

local function SetProtectedBagIcon(button, protected)
    if type(button) ~= "table" or not IsCallable(button.CreateTexture) then return end
    if protected then
        if not button.wowNoteProtectedIcon then
            local icon = button:CreateTexture(nil, "OVERLAY")
            icon:SetTexture(PROTECTED_ICON_TEXTURE)
            icon:SetWidth(14)
            icon:SetHeight(14)
            icon:ClearAllPoints()
            icon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
            button.wowNoteProtectedIcon = icon
        end
        if IsCallable(button.wowNoteProtectedIcon.Show) then button.wowNoteProtectedIcon:Show() end
    elseif button.wowNoteProtectedIcon and IsCallable(button.wowNoteProtectedIcon.Hide) then
        button.wowNoteProtectedIcon:Hide()
    end
end

GetBagSlotFromButton = function(button)
    if type(button) ~= "table" then return nil, nil end
    local bag, slot

    local parent = SafeCallMethod(button, "GetParent")
    if type(parent) == "table" and IsCallable(parent.GetID) then
        bag = parent:GetID()
    end
    if IsCallable(button.GetID) then slot = button:GetID() end

    -- ElvUI/skin bag buttons often keep their own bag/slot fields instead of
    -- using Blizzard's ContainerFrame parent IDs. Reading these fields lets the
    -- protection work without replacing UseContainerItem, which taints WotLK.
    bag = button.bagID or button.BagID or button.bag or button.Bag or bag
    slot = button.slotID or button.SlotID or button.slot or button.Slot or slot
    if (not bag or not slot) and type(parent) == "table" then
        bag = bag or parent.bagID or parent.BagID or parent.bag or parent.Bag
        slot = slot or parent.slotID or parent.SlotID or parent.slot or parent.Slot
    end
    return bag, slot
end

local function SetMerchantButtonBlocked(button, blocked)
    if type(button) ~= "table" then return end
    local canSetScript = IsCallable(button.SetScript)
    local canGetScript = IsCallable(button.GetScript)

    if blocked then
        if not button.wowNoteMerchantProtectedDisabled then
            button.wowNoteMerchantProtectedDisabled = true
            merchantProtectedButtons[button] = true
            if canSetScript then
                if canGetScript then button.wowNoteOriginalOnClick = button:GetScript("OnClick") end
                button:SetScript("OnClick", function(self, mouseButton, ...)
                    local bag, slot = GetBagSlotFromButton(self)
                    local link = GetProtectedBagSlotLink(bag, slot)
                    BlockedMessage("manual vendor sale", link or "protected item")
                    if UIErrorsFrame and UIErrorsFrame.AddMessage then
                        UIErrorsFrame:AddMessage("DO NOT SELL - protected item", 1, 0, 0, 1.0)
                    end
                    QueueBuybackGuard()
                end)
            elseif IsCallable(button.EnableMouse) then
                button:EnableMouse(false)
            end
            if IsCallable(button.LockHighlight) then button:LockHighlight() end
        end
    elseif button.wowNoteMerchantProtectedDisabled then
        button.wowNoteMerchantProtectedDisabled = nil
        merchantProtectedButtons[button] = nil
        if canSetScript then
            button:SetScript("OnClick", button.wowNoteOriginalOnClick)
            button.wowNoteOriginalOnClick = nil
        end
        if IsCallable(button.EnableMouse) then button:EnableMouse(true) end
        if IsCallable(button.UnlockHighlight) then button:UnlockHighlight() end
    end
end

local function VisitBlizzardContainerButtons(callback)
    local frameCount = NUM_CONTAINER_FRAMES or 13
    local maxSlots = MAX_CONTAINER_ITEMS or 36
    for frameIndex = 1, frameCount do
        for slotIndex = 1, maxSlots do
            local button = _G and _G["ContainerFrame" .. frameIndex .. "Item" .. slotIndex]
            if type(button) == "table" then callback(button) end
        end
    end
end

local function VisitLikelyCustomBagButtons(callback)
    -- Merchant-only pass for ElvUI/other bag replacements. Kept behind the
    -- merchant check so it cannot add regular inventory-click overhead.
    if not _G then return end
    for _, object in pairs(_G) do
        if type(object) == "table" and IsCallable(object.EnableMouse) and IsCallable(object.GetObjectType) then
            local bag = object.bagID or object.BagID or object.bag or object.Bag
            local slot = object.slotID or object.SlotID or object.slot or object.Slot
            if bag and slot then callback(object) end
        end
    end
end

UpdateMerchantProtectedButtons = function(includeCustomScan)
    local db = EnsureDB()
    local shouldBlock = db.blockManual ~= false and IsMerchantWindowOpen()
    local seen = {}

    local function updateButton(button)
        if type(button) ~= "table" then return end
        seen[button] = true
        local bag, slot = GetBagSlotFromButton(button)
        local link = GetProtectedBagSlotLink(bag, slot)
        SetProtectedBagIcon(button, link and true or false)
        if shouldBlock then
            SetMerchantButtonBlocked(button, link and true or false)
        else
            SetMerchantButtonBlocked(button, false)
        end
    end

    VisitBlizzardContainerButtons(updateButton)
    -- Custom-bag scanning walks _G and is intentionally limited to merchant
    -- windows so normal bag updates stay cheap. Blizzard bags always get the
    -- small protection icon above.
    if shouldBlock and includeCustomScan then VisitLikelyCustomBagButtons(updateButton) end

    for button in pairs(merchantProtectedButtons) do
        if not seen[button] then SetMerchantButtonBlocked(button, false) end
    end
end

QueueMerchantButtonUpdate = function(includeCustomScan, delay)
    if pendingMerchantButtonUpdate then return end
    pendingMerchantButtonUpdate = true
    local function run()
        pendingMerchantButtonUpdate = false
        if UpdateMerchantProtectedButtons then UpdateMerchantProtectedButtons(includeCustomScan and true or false) end
    end
    delay = tonumber(delay) or pendingMerchantButtonUpdateDelay
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, run)
    else
        if not merchantButtonTimerFrame then merchantButtonTimerFrame = CreateFrame("Frame") end
        local elapsedTotal = 0
        merchantButtonTimerFrame:SetScript("OnUpdate", function(self, elapsed)
            elapsedTotal = elapsedTotal + (elapsed or 0)
            if elapsedTotal >= delay then
                self:SetScript("OnUpdate", nil)
                run()
            end
        end)
    end
end

local function TryBuyBackProtectedItem()
    local db = EnsureDB()
    if db.blockManual == false or not IsMerchantWindowOpen() then return end
    if buybackGuardRunning then return end
    if type(BuybackItem) ~= "function" then return end
    local now = GetTime and GetTime() or time()
    if lastBuybackCheckAt and (now - lastBuybackCheckAt) < 0.05 then return end
    lastBuybackCheckAt = now

    local maxSlots = 12
    for index = 1, maxSlots do
        local link
        if type(GetBuybackItemLink) == "function" then
            link = GetBuybackItemLink(index)
        end
        if not link and type(GetBuybackItemInfo) == "function" then
            local name = GetBuybackItemInfo(index)
            if name then link = name end
        end
        if link and WowNote_IsItemProtected and WowNote_IsItemProtected(link) then
            buybackGuardRunning = true
            lastBuybackProtectedLink = link
            BuybackItem(index)
            BlockedMessage("manual vendor sale", link)
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("DO NOT SELL - protected item restored", 1, 0, 0, 1.0)
            end
            if RaidWarningFrame and RaidWarningFrame.AddMessage then
                RaidWarningFrame:AddMessage("DO NOT SELL", ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or nil)
            end
            if PlaySoundFile then
                PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
            elseif PlaySound then
                PlaySound("RaidWarning")
            end
            buybackGuardRunning = false
            return
        end
    end
end


QueueBuybackGuard = function()
    if pendingBuybackCheck then return end
    pendingBuybackCheck = true
    local function run()
        pendingBuybackCheck = false
        TryBuyBackProtectedItem()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, run)
    else
        if not buybackTimerFrame then buybackTimerFrame = CreateFrame("Frame") end
        local elapsedTotal = 0
        buybackTimerFrame:SetScript("OnUpdate", function(self, elapsed)
            elapsedTotal = elapsedTotal + (elapsed or 0)
            if elapsedTotal >= 0.05 then
                self:SetScript("OnUpdate", nil)
                run()
            end
        end)
    end
end

local function IsProtectedButtonAtMerchant(button)
    local db = EnsureDB()
    if db.blockManual == false or not IsMerchantWindowOpen() then return nil end
    local bag, slot = GetBagSlotFromButton(button)
    local link = GetProtectedBagSlotLink(bag, slot)
    if link then
        lastProtectedVendorAttemptAt = GetTime and GetTime() or time()
        BlockedMessage("manual vendor sale", link)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("DO NOT SELL - protected item", 1, 0, 0, 1.0)
        end
        QueueBuybackGuard()
        return true
    end
    return nil
end

local function InstallDeleteProtection()
    if not StaticPopupDialogs or type(StaticPopupDialogs) ~= "table" then return end
    local dialog = StaticPopupDialogs["DELETE_ITEM"]
    if type(dialog) ~= "table" or dialog.wowNoteWrapped then return end
    local originalOnAccept = dialog.OnAccept
    dialog.OnAccept = function(self, ...)
        local db = EnsureDB()
        if db.blockManual ~= false then
            local entry = GetCursorItemLinkOrId()
            if entry and WowNote_IsItemProtected and WowNote_IsItemProtected(entry) then
                BlockedMessage("delete", entry)
                if UIErrorsFrame and UIErrorsFrame.AddMessage then
                    UIErrorsFrame:AddMessage("DO NOT DELETE - protected item", 1, 0, 0, 1.0)
                end
                if ClearCursor then ClearCursor() end
                return
            end
        end
        if type(originalOnAccept) == "function" then
            return originalOnAccept(self, ...)
        end
    end
    dialog.wowNoteWrapped = true
end

local function InstallWrappers()
    -- Do NOT replace UseContainerItem/PickupContainerItem/DeleteCursorItem.
    -- Use pre-click blocking on container buttons and a buyback safety net.
    if wrappersInstalled then return end
    wrappersInstalled = true

    merchantEventFrame = CreateFrame("Frame")
    merchantEventFrame:RegisterEvent("MERCHANT_SHOW")
    merchantEventFrame:RegisterEvent("MERCHANT_CLOSED")
    merchantEventFrame:RegisterEvent("MERCHANT_UPDATE")
    merchantEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    if merchantEventFrame.RegisterEvent then merchantEventFrame:RegisterEvent("ITEM_LOCK_CHANGED") end
    merchantEventFrame:SetScript("OnEvent", function(self, event)
        if event == "MERCHANT_SHOW" then
            InstallDeleteProtection()
            QueueMerchantButtonUpdate(true, 0.05)
            QueueBuybackGuard()
        elseif event == "MERCHANT_CLOSED" then
            if UpdateMerchantProtectedButtons then UpdateMerchantProtectedButtons(false) end
        elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" then
            QueueMerchantButtonUpdate(false, 0.35)
        elseif event == "MERCHANT_UPDATE" then
            -- Always check buyback after a vendor update. It is cheap and is the
            -- only reliable fallback for ElvUI/other bag addons that bypass
            -- Blizzard's ContainerFrameItemButton_OnClick.
            QueueBuybackGuard()
        end
    end)

    InstallDeleteProtection()

    if hooksecurefunc then
        if type(ContainerFrameItemButton_OnModifiedClick) == "function" then
            hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", QuickProtectBagButton)
        end
        if type(ContainerFrameItemButton_OnClick) == "function" then
            hooksecurefunc("ContainerFrameItemButton_OnClick", QuickProtectBagButton)
        end
        if type(UseContainerItem) == "function" then
            hooksecurefunc("UseContainerItem", function(bag, slot)
                local db = EnsureDB()
                if db.blockManual ~= false and IsMerchantWindowOpen() then
                    QueueBuybackGuard()
                end
            end)
        end
        if type(ContainerFrame_Update) == "function" then
            hooksecurefunc("ContainerFrame_Update", function() QueueMerchantButtonUpdate(false, 0.05) end)
        end
        if type(ContainerFrame_GenerateFrame) == "function" then
            hooksecurefunc("ContainerFrame_GenerateFrame", function() QueueMerchantButtonUpdate(false, 0.05) end)
        end
        if type(StaticPopup_Show) == "function" then
            hooksecurefunc("StaticPopup_Show", function(which)
                if which == "DELETE_ITEM" then InstallDeleteProtection() end
            end)
        end
    end
end


local function AddBagTooltipHint(tooltip, bag, slot)
    if not tooltip or not bag or not slot then return end
    local link = GetProtectedBagSlotLink(bag, slot)
    if not link then return end
    if tooltip.AddLine then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffff0000==============================|r")
        tooltip:AddLine("|cffff0000        DO NOT SELL        |r")
        tooltip:AddLine("|cffff0000==============================|r")
        tooltip:AddLine("|cffff5555WoWNote: Protected item|r")
        tooltip:AddLine("|cffaaaaaaManual vendor selling/deleting is blocked. If sold anyway, WowNote attempts instant buyback.|r")
    end
    if tooltip.Show then tooltip:Show() end
    local tooltipName = tooltip.GetName and tooltip:GetName()
    if tooltipName and _G then
        local lines = tooltip.NumLines and tooltip:NumLines() or 0
        for i = math.max(1, lines - 4), lines do
            local fs = _G[tooltipName .. "TextLeft" .. tostring(i)]
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0, 0) end
            if fs and fs.SetFont and STANDARD_TEXT_FONT then fs:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE") end
        end
    end
end

local function EnsureBagTooltipHook()
    if bagTooltipHookInstalled then return end
    bagTooltipHookInstalled = true
    if hooksecurefunc and GameTooltip and GameTooltip.SetBagItem then
        pcall(function()
            hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
                AddBagTooltipHint(self, bag, slot)
            end)
        end)
    end
end

local function ProtectCurrentCursorOrArm()
    if not WowNote_QuickAddCursorItemToProtection() then
        SetStatus("Quick add armed. Click a bag item to protect it. You can also Alt+Shift-click bag items anytime.")
    else
        SetStatus("Protected cursor item.")
    end
end


local function GetCurrentProtectionLine()
    if not listEdit then return "" end
    local selected = listEdit:GetText()
    if listEdit.GetTextHighlight then
        local ok, highlighted = pcall(listEdit.GetTextHighlight, listEdit)
        if ok and highlighted and Trim(highlighted) ~= "" then return Trim(highlighted) end
    end
    local text = listEdit:GetText() or ""
    local cursor = 0
    if listEdit.GetCursorPosition then
        cursor = listEdit:GetCursorPosition() or 0
    end
    cursor = cursor + 1
    local startPos = cursor
    while startPos > 1 and string.sub(text, startPos - 1, startPos - 1) ~= "\n" do
        startPos = startPos - 1
    end
    local endPos = cursor
    while endPos <= string.len(text) and string.sub(text, endPos, endPos) ~= "\n" do
        endPos = endPos + 1
    end
    return Trim(string.sub(text, startPos, endPos - 1))
end

local function RemoveSelectedProtectionEntry()
    local entry = GetCurrentProtectionLine()
    if entry == "" then
        SetStatus("Select a protected item line first, or place the cursor in the line to remove.")
        return
    end
    if RemoveEntry(entry) then
        SetStatus("Removed protected item: " .. tostring(entry))
        Print("Removed protected item: " .. tostring(entry))
    else
        SetStatus("Protected item not found: " .. tostring(entry))
        Print("Protected item not found: " .. tostring(entry))
    end
end

local function ProtectEquipmentSetItems()
    local added = 0
    if not GetNumEquipmentSets or not GetEquipmentSetInfo then
        SetStatus("Equipment Manager API is not available on this client.")
        return
    end
    local numSets = GetNumEquipmentSets() or 0
    for index = 1, numSets do
        local name, icon, setID = GetEquipmentSetInfo(index)
        local ok, ids = false, nil
        if GetEquipmentSetItemIDs then
            ok, ids = pcall(GetEquipmentSetItemIDs, name)
            if not ok or type(ids) ~= "table" then
                ok, ids = pcall(GetEquipmentSetItemIDs, setID)
            end
        end
        if ok and type(ids) == "table" then
            for _, itemId in pairs(ids) do
                itemId = tonumber(itemId)
                if itemId and itemId > 0 then
                    AddEntry(tostring(itemId), true)
                    added = added + 1
                end
            end
        end
    end
    if listEdit then listEdit:SetText(WowNote_GetProtectedItemListText() or "") end
    SetStatus("Protected " .. tostring(added) .. " item ID(s) from Equipment Manager sets.")
end


local function ReserveEquipmentSetSlots()
    if type(WowNote_BagOrganizer_ReserveEquipmentSetSlots) ~= "function" then
        SetStatus("Bag Organizer module is not loaded yet.")
        return
    end
    local reserved, missing = WowNote_BagOrganizer_ReserveEquipmentSetSlots()
    SetStatus("Reserved " .. tostring(reserved or 0) .. " current set item slot(s); " .. tostring(missing or 0) .. " set item(s) not found in bags.")
end

SetListEditTextSafe = function(text)
    if not listEdit then return end
    suppressEditDirty = true
    listEdit:SetText(text or "")
    suppressEditDirty = false
    editDirty = false
end

local function PersistManualBlock(value)
    local checked = value and true or false
    local db = EnsureDB(true)
    db.blockManual = checked
    db.blockManualDelete = checked
    db.blockManualVendor = checked

    -- Write the flag directly to every SavedVariables mirror. Do not wait for
    -- OnHide/PLAYER_LOGOUT, because logout-time UI state can be stale or hidden.
    if type(WowNoteItemProtectionCharDB) ~= "table" then WowNoteItemProtectionCharDB = {} end
    WowNoteItemProtectionCharDB.blockManual = checked
    WowNoteItemProtectionCharDB.blockManualDelete = checked
    WowNoteItemProtectionCharDB.blockManualVendor = checked

    if type(WowNoteItemProtectionDB) ~= "table" then WowNoteItemProtectionDB = {} end
    WowNoteItemProtectionDB.blockManual = checked
    WowNoteItemProtectionDB.blockManualDelete = checked
    WowNoteItemProtectionDB.blockManualVendor = checked
    local key = GetCharacterKey()
    if key ~= "UNKNOWN" then
        if type(WowNoteItemProtectionDB.characters) ~= "table" then WowNoteItemProtectionDB.characters = {} end
        if type(WowNoteItemProtectionDB.characters[key]) ~= "table" then WowNoteItemProtectionDB.characters[key] = {} end
        WowNoteItemProtectionDB.characters[key].blockManual = checked
        WowNoteItemProtectionDB.characters[key].blockManualDelete = checked
        WowNoteItemProtectionDB.characters[key].blockManualVendor = checked
    end

    if type(WowNoteDB) ~= "table" then WowNoteDB = {} end
    if type(WowNoteDB.itemProtection) ~= "table" then WowNoteDB.itemProtection = {} end
    WowNoteDB.itemProtection.blockManual = checked
    WowNoteDB.itemProtection.blockManualDelete = checked
    WowNoteDB.itemProtection.blockManualVendor = checked
    if key ~= "UNKNOWN" then
        if type(WowNoteDB.itemProtection.characters) ~= "table" then WowNoteDB.itemProtection.characters = {} end
        if type(WowNoteDB.itemProtection.characters[key]) ~= "table" then WowNoteDB.itemProtection.characters[key] = {} end
        WowNoteDB.itemProtection.characters[key].blockManual = checked
        WowNoteDB.itemProtection.characters[key].blockManualDelete = checked
        WowNoteDB.itemProtection.characters[key].blockManualVendor = checked
    end

    if type(WowNoteCharDB) ~= "table" then WowNoteCharDB = {} end
    if type(WowNoteCharDB.itemProtection) ~= "table" then WowNoteCharDB.itemProtection = {} end
    WowNoteCharDB.itemProtection.blockManual = checked
    WowNoteCharDB.itemProtection.blockManualDelete = checked
    WowNoteCharDB.itemProtection.blockManualVendor = checked

    if SyncProtectionBackup then SyncProtectionBackup(db) end
    return db, checked
end

local function SaveControls(force)
    local db = EnsureDB(true)
    -- Manual UI saves are authoritative. Do not recover/merge backup lists here,
    -- otherwise removed items get resurrected from legacy mirrors.
    if listEdit then
        local uiText = NormalizeListText(listEdit:GetText() or "")
        if editDirty or force then
            db.protectedItems = uiText
            SetProtectionClearMarkerAll(db, IsListEmpty(uiText))
            SetProtectionAuthoritativeMarkerAll(db, true)
        elseif IsListEmpty(uiText) and not IsListEmpty(db.protectedItems or "") then
            -- Automatic OnHide/OnEditFocusLost must never wipe a restored list.
            SetListEditTextSafe(db.protectedItems or "")
        else
            db.protectedItems = uiText
            if not IsListEmpty(uiText) then SetProtectionClearMarkerAll(db, false) end
        end
    end

    -- Critical: do not read the checkbox during logout unless the user actually
    -- changed it in this UI session or explicitly pressed Save. Hidden frames can
    -- report a stale unchecked state and overwrite the real SavedVariables value.
    if manualBlockCheck and (force or manualBlockDirty or (frame and frame:IsShown())) then
        local checked = manualBlockCheck:GetChecked() and true or false
        db, checked = PersistManualBlock(checked)
        manualBlockDirty = false
    else
        if SyncProtectionBackup then SyncProtectionBackup(db) end
    end

    if QueueMerchantButtonUpdate then QueueMerchantButtonUpdate(false, 0.05) elseif UpdateMerchantProtectedButtons then UpdateMerchantProtectedButtons(false) end
    if listEdit then SetListEditTextSafe(db.protectedItems or "") end
    SetStatus("Item Protection saved: " .. tostring(CountProtectedLines(db.protectedItems or "")) .. " item(s). Manual block: " .. ((db.blockManual ~= false) and "ON" or "OFF"))
end

function WowNote_GetProtectedItemListText()
    local db = EnsureDB(true)
    return NormalizeListText(db.protectedItems or "")
end

function WowNote_ItemProtection_ForceSave()
    SaveControls(true)
    local db = EnsureDB(true)
    return CountProtectedLines(db.protectedItems or "")
end

function WowNote_ItemProtection_DebugPrint()
    local db = EnsureDB(true)
    local charStore, accountStore, key = EnsureStandaloneStores()
    Print("Item Protection debug: character=" .. tostring(key)
        .. ", protected=" .. tostring(CountProtectedLines(db.protectedItems or ""))
        .. ", blockManual=" .. tostring(db.blockManual ~= false)
        .. ", cleared=" .. tostring(db.protectionListCleared == true)
        .. ", authoritative=" .. tostring(db.protectionListAuthoritative == true))
end

local function UpdateControls()
    local db = EnsureDB(false)
    -- Only recover from old mirrors when the current list is empty. Opening the UI
    -- must not resurrect entries the user deliberately removed earlier.
    if IsListEmpty(db.protectedItems or "") and not IsRecoverySuppressed(db) and RecoverProtectionFromAllStores then RecoverProtectionFromAllStores(db, true) end
    if listEdit then SetListEditTextSafe(WowNote_GetProtectedItemListText() or "") end
    if manualBlockCheck then manualBlockCheck:SetChecked(db.blockManual ~= false) end
    manualBlockDirty = false
    SetStatus("Loaded " .. tostring(CountProtectedLines(db.protectedItems or "")) .. " protected item(s). Manual block: " .. ((db.blockManual ~= false) and "ON" or "OFF"))
end

local function RaiseFrame(target)
    if not target then return end
    if WowNote_Internal and WowNote_Internal.RaiseFrame then
        WowNote_Internal.RaiseFrame(target)
        return
    end
    target:SetFrameStrata("FULLSCREEN_DIALOG")
    target:SetFrameLevel(100)
    target:SetToplevel(true)
    if target.Raise then target:Raise() end
end

local function MakeButton(parent, text, width, height, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    return button
end

local function MakeLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function MakeSmallText(parent, text, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width or 450)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function MakeCheck(parent, text, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.text:SetPoint("LEFT", check, "RIGHT", -2, 0)
    check.text:SetText(text)
    check:SetScript("OnClick", function(self)
        manualBlockDirty = true
        local db, checked = PersistManualBlock(self:GetChecked() and true or false)
        if QueueMerchantButtonUpdate then QueueMerchantButtonUpdate(false, 0.05) elseif UpdateMerchantProtectedButtons then UpdateMerchantProtectedButtons(false) end
        SetStatus("Manual merchant/delete blocking: " .. (checked and "ON" or "OFF") .. " (saved now)")
    end)
    return check
end


local function EnsureTextAreaLinkHook()
    if linkHookInstalled then return end
    linkHookInstalled = true
    local originalInsertLink = ChatEdit_InsertLink
    if type(originalInsertLink) == "function" then
        ChatEdit_InsertLink = function(link)
            if activeTextArea and activeTextArea:IsVisible() and activeTextArea:HasFocus() then
                activeTextArea:Insert(link)
                return true
            end
            return originalInsertLink(link)
        end
    end
end

local function MakeTextArea(parent, width, height, x, y)
    EnsureTextAreaLinkHook()

    local bg = CreateFrame("Frame", nil, parent)
    bg:EnableMouse(true)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetSize(width, height)
    bg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    bg:SetBackdropColor(0, 0, 0, 0.85)

    textAreaCounter = textAreaCounter + 1
    local scroll = CreateFrame("ScrollFrame", "WowNoteItemProtectionScroll" .. textAreaCounter, bg, "UIPanelScrollFrameTemplate")
    scroll:EnableMouse(true)
    scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 4)

    local edit = CreateFrame("EditBox", "WowNoteItemProtectionEdit" .. textAreaCounter, scroll)
    edit:EnableMouse(true)
    edit:EnableKeyboard(true)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(width - 36)
    edit:SetHeight(height * 2)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); SaveControls(false) end)
    edit:SetScript("OnEditFocusLost", function(self) if activeTextArea == self then activeTextArea = nil end; SaveControls(false) end)
    edit:SetScript("OnEditFocusGained", function(self) activeTextArea = self end)
    edit:SetScript("OnMouseDown", function(self) self:SetFocus(); activeTextArea = self end)
    edit:SetScript("OnCursorChanged", function(self, cx, cy, cw, ch)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, cx, cy, cw, ch) end
    end)
    if WowNoteProfiler_SetScript then
        WowNoteProfiler_SetScript(edit, "OnUpdate", "ItemProtection.EditBox", function(self, elapsed)
            if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, self:GetParent()) end
        end)
    else
        edit:SetScript("OnUpdate", function(self, elapsed)
            if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, self:GetParent()) end
        end)
    end
    edit:SetScript("OnTextChanged", function(self)
        if not suppressEditDirty then editDirty = true end
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, self:GetParent()) end
    end)
    bg:SetScript("OnMouseDown", function() edit:SetFocus(); activeTextArea = edit end)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus(); activeTextArea = edit end)
    scroll:SetScrollChild(edit)
    return edit
end

local function CreateUI()
    if frame then return end
    frame = CreateFrame("Frame", "WowNoteItemProtectionFrame", UIParent)
    frame:SetSize(560, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function() SaveControls(false) end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.97)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("WowNote Item Protection")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    MakeSmallText(frame, "Items in this list are blocked from WowNote Auto Sell, Auto Roll disenchant/greed, manual merchant selling and delete helpers. Alt+Shift-click a bag item to protect it instantly. Bag Organizer: hover a bag slot and press the keybinding 'Reserve hovered bag slot' (default R) to reserve that slot. 'Reserve Set Slots' stores current set item positions and adds to existing slot rules.", 28, -48, 500)

    manualBlockCheck = MakeCheck(frame, "Block manual merchant selling and deletion (saved)", 28, -92)

    MakeLabel(frame, "Protected items: one item link, item ID or exact item name per line", 28, -132)
    listEdit = MakeTextArea(frame, 500, 230, 28, -150)

    local save = MakeButton(frame, "Save", 80, 24, 28, -395)
    save:SetScript("OnClick", function() SaveControls(true) end)

    local quick = MakeButton(frame, "Quick Protect", 120, 24, 118, -395)
    quick:SetScript("OnClick", ProtectCurrentCursorOrArm)

    local sets = MakeButton(frame, "Protect Sets", 110, 24, 248, -395)
    sets:SetScript("OnClick", ProtectEquipmentSetItems)

    local reserveSets = MakeButton(frame, "Reserve Set Slots", 145, 24, 368, -395)
    reserveSets:SetScript("OnClick", ReserveEquipmentSetSlots)
    reserveSets:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Reserve Set Slots", 1, 0.82, 0)
            GameTooltip:AddLine("Uses the current bag positions of Equipment Manager set items as their reserved Bag Organizer slots.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("If a slot already has a rule, the set item is added to that slot's priority list instead of replacing it.", 0.7, 0.9, 1, true)
            GameTooltip:Show()
        end
    end)
    reserveSets:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local normalize = MakeButton(frame, "Sort/Dedupe", 100, 24, 28, -425)
    normalize:SetScript("OnClick", function() SaveControls(true) end)

    local remove = MakeButton(frame, "Remove selected", 140, 24, 138, -425)
    remove:SetScript("OnClick", RemoveSelectedProtectionEntry)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 28, 18)
    statusText:SetWidth(500)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Ready")

    frame:Hide()
end

function WowNote_OpenItemProtection()
    CreateUI()
    UpdateControls()
    frame:Show()
    RaiseFrame(frame)
end

function WowNote_ItemProtectionHandleSlash(msg)
    local command = Lower(msg or "")
    if command == "" or command == "show" or command == "config" then
        WowNote_OpenItemProtection()
    elseif command == "add" or command == "quick" or command == "protect" then
        WowNote_QuickAddCursorItemToProtection()
    elseif command == "sets" or command == "equipmentsets" then
        ProtectEquipmentSetItems()
    elseif command == "save" or command == "forcesave" then
        local count = WowNote_ItemProtection_ForceSave and WowNote_ItemProtection_ForceSave() or 0
        Print("Item Protection saved: " .. tostring(count) .. " protected item(s).")
    elseif command == "debug" then
        if WowNote_ItemProtection_DebugPrint then WowNote_ItemProtection_DebugPrint() end
    elseif string.sub(command, 1, 4) == "add " then
        local entry = Trim(string.sub(msg or "", 5))
        AddEntry(entry)
    elseif string.sub(command, 1, 7) == "remove " then
        local entry = Trim(string.sub(msg or "", 8))
        if RemoveEntry(entry) then Print("Removed protected item: " .. entry) else Print("Protected item not found: " .. entry) end
    else
        Print("Item Protection commands: /wn protect, /wn protect add <itemID|name|link>, /wn protect remove <itemID|name|link>, /wn protect sets, /wn protect save, /wn protect debug")
    end
end

local function InstallItemProtectionEvents()
    if itemProtectionEventFrame then return end
    itemProtectionEventFrame = CreateFrame("Frame")
    itemProtectionEventFrame:RegisterEvent("ADDON_LOADED")
    itemProtectionEventFrame:RegisterEvent("PLAYER_LOGIN")
    itemProtectionEventFrame:RegisterEvent("PLAYER_LOGOUT")
    itemProtectionEventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
    itemProtectionEventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" and arg1 ~= "WowNote" then return end
        if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
            local db = EnsureDB()
            if RecoverProtectionFromAllStores then RecoverProtectionFromAllStores(db, true) end
            if frame and frame:IsShown() then UpdateControls() end
            if SyncProtectionBackup then SyncProtectionBackup(db) end
        else
            local db = EnsureDB()
            -- On logout/leaving world, never pull a checkbox value from a hidden UI.
            -- The checkbox already persists immediately in its OnClick handler.
            if listEdit and editDirty then
                db.protectedItems = NormalizeListText(listEdit:GetText() or "")
                SetProtectionClearMarkerAll(db, IsListEmpty(db.protectedItems or ""))
            end
            if SyncProtectionBackup then SyncProtectionBackup(db) end
        end
    end)
end

-- Do not rely on top-level SavedVariables state; ADDON_LOADED/PLAYER_LOGIN initializes storage.
InstallWrappers()
EnsureBagTooltipHook()
InstallItemProtectionEvents()
