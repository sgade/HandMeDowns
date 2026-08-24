--[[----------------------------------------------------------------------------

  WarbandMeDowns/Characters.lua
  Warband character enumeration/priority and DataStore-backed eligibility
  checks (class/spec weapon and shield preferences, equipped-item lookup,
  bag/bank iteration). See WarbandMeDowns.lua for the license header covering
  the whole addon.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Characters = WarbandMeDowns.Characters or {}
local Characters = WarbandMeDowns.Characters
local Data = WarbandMeDowns.Data

-- *** Specialization resolution

local WarnedMissingSpecAPI = false
local KnownSpecIndexCache = {}
local SpecUnknown = {}

---Resolves the active specialization of a character as Blizzard's *local
---spec index* (1-4), if known.
---
---This is exactly what DataStore hands back and must not be confused with a
---global spec ID: DataStore_Talents stores the value
---C_SpecializationInfo.GetSpecialization() returns, packed into three bits
---(`bit64:GetBits(info, 0, 3)` in DataStore_Talents/API/Specialization.lua),
---so it can only ever be 1-4. Global spec IDs start at 62, so treating this
---as one silently matches nothing at all - which is precisely what used to
---make both the Pawn scale lookup and the per-spec weapon filtering below
---dead code. Use WarbandMeDowns.Characters.GetKnownSpecID when a global ID is
---what's wanted.
---
---Requires the optional DataStore_Talents module and a character that has
---been scanned at least once; returns `nil` otherwise, which callers must
---treat as "spec unknown", never as "cannot use anything".
---@param character string
---@return number? localSpecIndex
function Characters.GetKnownSpecIndex(character)
    local cached = KnownSpecIndexCache[character]
    if cached == SpecUnknown then
        return nil
    elseif cached then
        return cached
    end

    local result = (function()
        if not DataStore.GetActiveSpecInfo then
            --@alpha@
            if not WarnedMissingSpecAPI then
                WarnedMissingSpecAPI = true
                WarbandMeDowns:Print("warn: DataStore.GetActiveSpecInfo not available.")
            end
            --@end-alpha@
            return nil
        end

        local success, _, specIndex = pcall(DataStore.GetActiveSpecInfo, DataStore, character)
        if not success or not specIndex or specIndex == 0 then
            return nil
        end

        -- Guard against a future DataStore change (or a class whose spec list
        -- we do not know) handing back something that is not a valid index
        -- into Data.SpecsByClass - better "spec unknown" than a wrong spec.
        local _, class = DataStore:GetCharacterClass(character)
        local specIDs = class and Data.SpecsByClass[class]
        if not specIDs or specIndex > #specIDs then
            return nil
        end

        return specIndex
    end)()

    KnownSpecIndexCache[character] = result or SpecUnknown
    return result
end

---The character's active specialization as a global, Blizzard-stable spec ID
---(the 62-1480 range in Data.Spec), translated from the local index DataStore
---actually stores via Data.SpecsByClass' index ordering.
---@param character string
---@return number? specID
function Characters.GetKnownSpecID(character)
    local specIndex = Characters.GetKnownSpecIndex(character)
    if not specIndex then
        return nil
    end

    local _, class = DataStore:GetCharacterClass(character)
    local specIDs = class and Data.SpecsByClass[class]
    return specIDs and specIDs[specIndex]
end

---Clears the per-character active-spec memo. Called by
---WarbandMeDowns.Assignment:Recompute() so a spec change is always picked up.
function Characters.ClearSpecCache()
    WarbandMeDowns.Util.clearTable(KnownSpecIndexCache)
end

---Checks whether a weapon or shield is one the character's specialization
---actually favors, falling back to the union over every spec of the
---character's class when the spec is unknown. Armor other than shields is
---never specialization-specific and always passes.
---@param character string
---@param class string
---@param itemClassID number
---@param itemSubclassID number
---@return boolean
function Characters.IsItemSubclassFavoredBySpec(character, class, itemClassID, itemSubclassID)
    if itemClassID == Data.ItemClassWeapon and itemSubclassID == Data.WeaponSubclass.FishingPole then
        return true
    end

    local isWeapon = itemClassID == Data.ItemClassWeapon
    local isShield = itemClassID == Data.ItemClassArmor and itemSubclassID == Data.ArmorSubclass.Shield
    if not isWeapon and not isShield then
        return true
    end

    -- Note this branch only started being reachable once GetKnownSpecID began
    -- returning a real global spec ID; it used to receive a 1-4 index, which
    -- never matched Data.SpecClass, so every character silently fell through
    -- to the class-wide union below.
    local specID = Characters.GetKnownSpecID(character)
    if specID and Data.SpecClass[specID] == class then
        if isShield then
            return Data.SpecUsesShield[specID] == true
        end
        local favoredBySpec = Data.SpecWeaponSubclasses[specID]
        if favoredBySpec then
            return favoredBySpec[itemSubclassID] == true
        end
    end

    if isShield then
        return Data.ClassUsesShield[class] == true
    end

    local favorites = Data.ClassFavoriteWeaponSubclasses[class]
    return favorites ~= nil and favorites[itemSubclassID] == true
end

-- *** Equip eligibility
--
-- CanCharacterEquipItemClass depends only on (character, classID,
-- subclassID) - never on the specific item link/level - so it's memoized on
-- that tuple and reused across every item and slot that shares it, instead
-- of being recomputed per item like the rest of the old single-item flow
-- was.

local WarnedItemSubclasses = {}
local EligibilityCache = {}

---@param character string
---@param classID number
---@param subclassID number
---@return boolean
function Characters.CanCharacterEquipItemClass(character, classID, subclassID)
    local characterCache = EligibilityCache[character]
    if not characterCache then
        characterCache = {}
        EligibilityCache[character] = characterCache
    end

    local classCache = characterCache[classID]
    if not classCache then
        classCache = {}
        characterCache[classID] = classCache
    end

    local cached = classCache[subclassID]
    if cached ~= nil then
        return cached
    end

    local result = (function()
        local classesThatCanUseItem = nil

        if classID == Data.ItemClassArmor then
            classesThatCanUseItem = Data.ArmorSubclassClasses[subclassID]
        elseif classID == Data.ItemClassWeapon then
            classesThatCanUseItem = Data.WeaponSubclassClasses[subclassID]
        else
            return false
        end

        if not classesThatCanUseItem then
            --@alpha@
            local warningKey = tostring(classID) .. "." .. tostring(subclassID)
            if not WarnedItemSubclasses[warningKey] then
                WarnedItemSubclasses[warningKey] = true
                WarbandMeDowns:Print("warn: unknown item subclass '" .. warningKey .. "'")
            end
            --@end-alpha@
            return false
        end

        local _, class = DataStore:GetCharacterClass(character)

        if not WarbandMeDowns.Util.arrayContains(classesThatCanUseItem, class) then
            return false
        end

        return Characters.IsItemSubclassFavoredBySpec(character, class, classID, subclassID)
    end)()

    classCache[subclassID] = result
    return result
end

---Clears the per-(character, classID, subclassID) eligibility memo. Called
---by WarbandMeDowns.Assignment:Recompute() whenever the warband might have
---changed (e.g. a spec change).
function Characters.ClearEligibilityCache()
    WarbandMeDowns.Util.clearTable(EligibilityCache)
end

---@param character string
---@param itemLink ItemInfo
---@return boolean
function Characters.CanCharacterEquipItem(character, itemLink)
    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    return Characters.CanCharacterEquipItemClass(character, classID, subclassID)
end

-- *** Reading what a character already has

---Every inventory slot an item worn at `equipLocation` could occupy, and
---what the character currently has in each one.
---
---The count is returned separately and the array is indexed 1..count with a
---nil for every *empty* slot, because an empty slot is load-bearing: a
---character wearing only one ring can take a new one for free, and `ipairs`
---or `#` would simply hide that hole. Callers must iterate `1, count`.
---@param character string
---@param equipLocation string
---@return ItemInfo[] equippedBySlot # 1..slotCount, nil entries mean an empty slot
---@return number slotCount
function Characters.GetEquippedItemsForEquipLocation(character, equipLocation)
    local slotId = Data.EquipLocToSlotID[equipLocation]
    if not slotId then
        return {}, 0
    end

    local getItem = function(slotId)
        return DataStore:GetInventoryItem(character, slotId)
    end

    if equipLocation == "INVTYPE_FINGER" then
        return { getItem(INVSLOT_FINGER1), getItem(INVSLOT_FINGER2) }, 2
    elseif equipLocation == "INVTYPE_TRINKET" then
        return { getItem(INVSLOT_TRINKET1), getItem(INVSLOT_TRINKET2) }, 2
    elseif equipLocation == "INVTYPE_WEAPON" then
        return { getItem(INVSLOT_MAINHAND), getItem(INVSLOT_OFFHAND) }, 2
    else
        return { getItem(slotId) }, 1
    end
end

-- Reimplementation from DataStore_Containers. DataStore_Containers stores both
-- bag and bank-like containers, depending on what has been scanned for a character.
---@param character string
---@param callback fun(containerId: number, container: table, slotId: number, itemId: number, itemLink: ItemInfo)
function Characters.IterateStoredContainerItems(character, callback)
    local containers = DataStore:GetContainers(character)
    if not containers then
        return
    end

    for containerId, container in pairs(containers) do
        local containerSize = DataStore:GetContainerSize(character, containerId) or 0
        for slotId = 1, containerSize do
            local itemId, itemLink = DataStore:GetSlotInfo(container, slotId)

            -- Callback only if there is an item in that slot
            if itemId and itemLink then
                callback(containerId, container, slotId, itemId, itemLink)
            end
        end
    end
end

---@param key string
---@return string?, string?
function Characters.CharacterServerAndNameFromKey(key)
    local _, server, name = strsplit(".", key)
    return server, name
end

---A character's display name for user-facing text: just the character name
---if it's unique across the warband, or "Name@Realm" if another warband
---character shares the same name on a different realm.
---@param character string
---@return string
function Characters.GetDisplayName(character)
    local server, name = Characters.CharacterServerAndNameFromKey(character)
    if not name then
        return character
    end

    for _, other in ipairs(Characters.GetWarbandCharacters()) do
        if other ~= character then
            local _, otherName = Characters.CharacterServerAndNameFromKey(other)
            if otherName == name then
                return name .. "@" .. (server or "?")
            end
        end
    end

    return name
end

-- *** Warband enumeration and priority

---Every character on the account - the current one included.
---
---DataStore.ThisAccount: usually "Default"
---DataStore:GetCharacters(): keys of the form "Default.Server.Name"
---assuming "this account" is the warband
---@return string[]
function Characters.GetWarbandCharacters()
    local characters = {}
    for realmName in pairs(DataStore:GetRealms(DataStore.ThisAccount)) do
        for _, character in pairs(DataStore:GetCharacters(realmName, DataStore.ThisAccount)) do
            table.insert(characters, character)
        end
    end
    return characters
end

---The warband priority order: current level first, then equipped average
---item level.
---
---EXTENSION POINT: this is the one place warband priority is decided.
---Replace this function reference to change the ordering later (e.g. a
---manual per-character order, or a different set of criteria) without
---touching anything that consumes WarbandMeDowns.Characters.GetSortedWarbandCharacters().
---Only this default is implemented today.
---@param left string
---@param right string
---@return boolean
function Characters.CharacterPriorityComparator(left, right)
    local leftLevel = DataStore:GetCharacterLevel(left) or 0
    local rightLevel = DataStore:GetCharacterLevel(right) or 0
    if leftLevel ~= rightLevel then
        return leftLevel > rightLevel
    end

    local leftItemLevel = DataStore:GetAverageItemLevel(left) or 0
    local rightItemLevel = DataStore:GetAverageItemLevel(right) or 0
    return leftItemLevel > rightItemLevel
end

---The warband, ranked by WarbandMeDowns.Characters.CharacterPriorityComparator.
---The current character is not special-cased: it's ranked like any other
---and wins only if it comes first among the characters that need an item.
---@return string[]
function Characters.GetSortedWarbandCharacters()
    local characters = Characters.GetWarbandCharacters()
    table.sort(characters, Characters.CharacterPriorityComparator)
    return characters
end
