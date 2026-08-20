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
local KnownSpecIDCache = {}
local SpecUnknown = {}

---Resolves the active specialization of a character, if known.
---Requires the optional DataStore_Talents module and a character that has
---been scanned at least once; returns `nil` otherwise, which callers must
---treat as "spec unknown", never as "cannot use anything".
---@param character string
---@return number? specID
function Characters.GetKnownSpecID(character)
    local cached = KnownSpecIDCache[character]
    if cached == SpecUnknown then
        return nil
    elseif cached then
        return cached
    end

    if not DataStore.GetActiveSpecInfo then
        --@alpha@
        if not WarnedMissingSpecAPI then
            WarnedMissingSpecAPI = true
            WarbandMeDowns:Print("warn: DataStore.GetActiveSpecInfo not available.")
        end
        --@end-alpha@
        KnownSpecIDCache[character] = SpecUnknown
        return nil
    end

    local success, _, specID = pcall(DataStore.GetActiveSpecInfo, DataStore, character)
    if not success or not specID or specID == 0 then
        KnownSpecIDCache[character] = SpecUnknown
        return nil
    end

    KnownSpecIDCache[character] = specID
    return specID
end

---Clears the per-character active-spec memo. Called by
---WarbandMeDowns.Assignment:Recompute() so a spec change is always picked up.
function Characters.ClearSpecCache()
    WarbandMeDowns.Util.clearTable(KnownSpecIDCache)
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

    local specID = Characters.GetKnownSpecID(character)
    if specID and Data.SpecClass[specID] == class then
        if isShield then
            return Data.SpecUsesShield[specID] == true
        end
        return Data.SpecWeaponSubclasses[specID][itemSubclassID] == true
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

---@param character string
---@param equipLocation string
---@return ItemInfo[]
function Characters.GetEquippedItemsForEquipLocation(character, equipLocation)
    local slotId = Data.EquipLocToSlotID[equipLocation]
    if not slotId then
        return {}
    end

    local getItem = function(slotId)
        return DataStore:GetInventoryItem(character, slotId)
    end

    if equipLocation == "INVTYPE_FINGER" then
        return {
            getItem(INVSLOT_FINGER1),
            getItem(INVSLOT_FINGER2)
        }
    elseif equipLocation == "INVTYPE_TRINKET" then
        return {
            getItem(INVSLOT_TRINKET1),
            getItem(INVSLOT_TRINKET2)
        }
    elseif equipLocation == "INVTYPE_WEAPON" then
        return {
            getItem(INVSLOT_MAINHAND),
            getItem(INVSLOT_OFFHAND)
        }
    else
        return { getItem(slotId) }
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
