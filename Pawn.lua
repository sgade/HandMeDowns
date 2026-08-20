--[[----------------------------------------------------------------------------

  HandMeDowns/Pawn.lua
  Item comparison via the optional Pawn addon
  (https://github.com/VgerMods/Pawn). See HandMeDowns.lua for the license
  header covering the whole addon.

  HandMeDowns does not maintain its own stat priorities. Instead, when Pawn
  is installed, its own item-scoring calculation is used as the authoritative
  comparison between two comparable items - item level is only used as a
  fallback when Pawn isn't installed/usable. See
  HandMeDowns.Assignment.CompareItemsForCharacter. Pawn is not a
  required dependency, and its functions are not a documented/versioned API
  - every call below is defensive (existence and type checks, pcall) and
  degrades silently to "no opinion" (the same fallback as an unknown spec)
  if Pawn isn't installed, is a different version than expected, or errors
  internally. See docs/DATA_SOURCES.md for exactly which Pawn functions this
  relies on, the Pawn version it was verified against, and how to re-verify
  them.

----------------------------------------------------------------------------]]--

HandMeDowns.Pawn = HandMeDowns.Pawn or {}
local Pawn = HandMeDowns.Pawn
local Data = HandMeDowns.Data
local Characters = HandMeDowns.Characters

local PawnScaleNameCache = {}
local PawnScaleUnknown = {}
local PawnItemValueCache = {} -- PawnItemValueCache[scaleName][itemLink] = number | false

---Finds the local (1-4) spec index Pawn expects, matching Blizzard's
---GetSpecializationInfoForClassID convention. Data.SpecsByClass is already
---ordered to match that convention (see Data.lua's SetClassSpecs calls).
---@param class string
---@param specID number
---@return number?
local function GetPawnLocalSpecIndex(class, specID)
    local specIDs = Data.SpecsByClass[class]
    if not specIDs then
        return nil
    end

    for index, thisSpecID in ipairs(specIDs) do
        if thisSpecID == specID then
            return index
        end
    end

    return nil
end

---Resolves the name of the Pawn scale to use for a character, if Pawn is
---installed and a scale can be determined. Never throws; returns nil for
---any reason Pawn's data isn't usable (not installed, spec unknown, a
---renamed/missing function, or an error inside Pawn itself).
---@param character string
---@return string?
function Pawn.GetPawnScaleNameForCharacter(character)
    local cached = PawnScaleNameCache[character]
    if cached == PawnScaleUnknown then
        return nil
    elseif cached then
        return cached
    end

    local result = (function()
        if type(PawnFindScaleForSpec) ~= "function" then
            return nil
        end

        local _, class = DataStore:GetCharacterClass(character)
        local classID = class and Data.ClassID[class]
        local specID = Characters.GetKnownSpecID(character)
        if not classID or not specID then
            return nil
        end

        local localSpecIndex = GetPawnLocalSpecIndex(class, specID)
        if not localSpecIndex then
            return nil
        end

        local ok, scaleName = pcall(PawnFindScaleForSpec, classID, localSpecIndex)
        if not ok or type(scaleName) ~= "string" then
            return nil
        end

        return scaleName
    end)()

    PawnScaleNameCache[character] = result or PawnScaleUnknown
    return result
end

---Clears the per-character Pawn scale-name memo and the per-item value
---cache. Called by HandMeDowns.Assignment:Recompute()/Reset() so a spec
---change or an item shuffling around the warband is always picked up.
function Pawn.ClearCaches()
    HandMeDowns.Util.clearTable(PawnScaleNameCache)
    HandMeDowns.Util.clearTable(PawnItemValueCache)
end

---Scores an item against a named Pawn scale, using Pawn's own item parsing
---and valuation. Never throws; returns nil for any reason a value couldn't
---be produced. Memoized per (scaleName, itemLink) for the current
---generation, since Assignment now scans the full candidate pool per
---character instead of stopping early, which can otherwise re-score the
---same item many times.
---@param itemLink ItemInfo
---@param scaleName string
---@return number?
function Pawn.GetPawnItemValue(itemLink, scaleName)
    if not itemLink then
        return nil
    end

    local scaleCache = PawnItemValueCache[scaleName]
    if scaleCache then
        local cached = scaleCache[itemLink]
        if cached ~= nil then
            return cached or nil
        end
    else
        scaleCache = {}
        PawnItemValueCache[scaleName] = scaleCache
    end

    local value = (function()
        if type(PawnGetItemData) ~= "function" or type(PawnGetSingleValueFromItem) ~= "function" then
            return nil
        end

        local ok, item = pcall(PawnGetItemData, itemLink)
        if not ok or type(item) ~= "table" then
            return nil
        end

        local ok2, result = pcall(PawnGetSingleValueFromItem, item, scaleName)
        if not ok2 or type(result) ~= "number" then
            return nil
        end

        return result
    end)()

    scaleCache[itemLink] = value or false
    return value
end

---Compares two items purely on Pawn's score against a resolved scale. A
---missing item (nil/false, an empty slot) always loses to a present,
---scoreable item, and ties against another missing item. Returns nil (no
---opinion) only when at least one *present* item couldn't be scored by
---Pawn, so the caller can fall back to a different comparison for that
---pair - see HandMeDowns.Assignment.CompareItemsForCharacter, the only
---caller.
---@param itemLinkA ItemInfo
---@param itemLinkB ItemInfo
---@param scaleName string
---@return integer? # 1 if A is preferred, -1 if B is preferred, 0 if tied, nil if unknown
function Pawn.CompareItemValuesForScale(itemLinkA, itemLinkB, scaleName)
    if not itemLinkA and not itemLinkB then
        return 0
    end

    local valueA = itemLinkA and Pawn.GetPawnItemValue(itemLinkA, scaleName)
    local valueB = itemLinkB and Pawn.GetPawnItemValue(itemLinkB, scaleName)
    if (itemLinkA and not valueA) or (itemLinkB and not valueB) then
        return nil
    end

    valueA = valueA or -math.huge
    valueB = valueB or -math.huge
    if valueA == valueB then
        return 0
    end

    return valueA > valueB and 1 or -1
end
