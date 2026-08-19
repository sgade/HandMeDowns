--[[----------------------------------------------------------------------------

  HandMeDowns/Pawn.lua
  Secondary stat tie-breaking via the optional Pawn addon
  (https://github.com/VgerMods/Pawn). See HandMeDowns.lua for the license
  header covering the whole addon.

  HandMeDowns does not maintain its own secondary stat priorities. Instead,
  when Pawn is installed, its own item-scoring calculation is used to break
  an exact item-level tie between two comparable items. Pawn is not a
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

---Clears the per-character Pawn scale-name memo. Called by
---HandMeDowns.Assignment:Recompute() so a spec change is always picked up.
function Pawn.ClearScaleCache()
    HandMeDowns.Util.clearTable(PawnScaleNameCache)
end

---Scores an item against a named Pawn scale, using Pawn's own item parsing
---and valuation. Never throws; returns nil for any reason a value couldn't
---be produced.
---@param itemLink ItemInfo
---@param scaleName string
---@return number?
function Pawn.GetPawnItemValue(itemLink, scaleName)
    if not itemLink or type(PawnGetItemData) ~= "function" or type(PawnGetSingleValueFromItem) ~= "function" then
        return nil
    end

    local ok, item = pcall(PawnGetItemData, itemLink)
    if not ok or type(item) ~= "table" then
        return nil
    end

    local ok2, value = pcall(PawnGetSingleValueFromItem, item, scaleName)
    if not ok2 or type(value) ~= "number" then
        return nil
    end

    return value
end

---Compares two items purely on secondary stats, by asking Pawn to score
---both against the character's spec scale. Only meaningful as a tie-break
---once item level is already known to be equal - see
---HandMeDowns.Assignment.CompareItemsForCharacter.
---@param character string
---@param itemLinkA ItemInfo
---@param itemLinkB ItemInfo
---@return integer # 1 if A is preferred, -1 if B is preferred, 0 if tied or unknown
function Pawn.CompareItemStatsForCharacter(character, itemLinkA, itemLinkB)
    local scaleName = Pawn.GetPawnScaleNameForCharacter(character)
    if not scaleName then
        -- Pawn isn't installed/usable, or the spec is unknown: no opinion,
        -- leave the tie as-is rather than guessing.
        return 0
    end

    local valueA = Pawn.GetPawnItemValue(itemLinkA, scaleName)
    local valueB = Pawn.GetPawnItemValue(itemLinkB, scaleName)
    if not valueA or not valueB or valueA == valueB then
        return 0
    end

    return valueA > valueB and 1 or -1
end
