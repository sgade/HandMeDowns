--[[----------------------------------------------------------------------------

  WarbandMeDowns/Pawn.lua
  Item comparison via the optional Pawn addon
  (https://github.com/VgerMods/Pawn). See WarbandMeDowns.lua for the license
  header covering the whole addon.

  WarbandMeDowns does not maintain its own stat priorities. Instead, when Pawn
  is installed, its own item-scoring calculation is used as the authoritative
  comparison between two comparable items - item level is only used as a
  fallback when Pawn isn't installed/usable. See
  WarbandMeDowns.Assignment.CompareItemsForCharacter. Pawn is not a
  required dependency, and its functions are not a documented/versioned API
  - every call below is defensive (existence and type checks, pcall) and
  degrades silently to "no opinion" (the same fallback as an unknown spec)
  if Pawn isn't installed, is a different version than expected, or errors
  internally. See docs/DATA_SOURCES.md for exactly which Pawn functions this
  relies on, the Pawn version it was verified against, and how to re-verify
  them.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Pawn = WarbandMeDowns.Pawn or {}
local Pawn = WarbandMeDowns.Pawn
local Data = WarbandMeDowns.Data
local Characters = WarbandMeDowns.Characters

local PawnScaleNameCache = {}
local PawnScaleUnknown = {}
local PawnItemValueCache = {} -- PawnItemValueCache[scaleName][itemLink] = number | false

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
        -- PawnFindScaleForSpec wants the local 1-4 spec index, which is
        -- exactly what DataStore stores - see
        -- WarbandMeDowns.Characters.GetKnownSpecIndex. An earlier version
        -- converted that index to a global spec ID and back again through
        -- Data.SpecsByClass, which could never match (global IDs start at 62),
        -- so this function returned nil for every character and Pawn was never
        -- consulted at all.
        local localSpecIndex = Characters.GetKnownSpecIndex(character)
        if not classID or not localSpecIndex then
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
---cache. Called by WarbandMeDowns.Assignment:Recompute()/Reset() so a spec
---change or an item shuffling around the warband is always picked up.
function Pawn.ClearCaches()
    wipe(PawnScaleNameCache)
    wipe(PawnItemValueCache)
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
