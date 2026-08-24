--[[----------------------------------------------------------------------------

  WarbandMeDowns/ItemLevel.lua
  Projected average item levels: where a character would land if they equipped
  everything they already carry ("max"), and where they would land once the
  assignment engine also sent them what it earmarked for them ("theoretical").
  Purely presentational - nothing here feeds a recommendation. See
  WarbandMeDowns.lua for the license header covering the whole addon.

  *** Why these are deltas on top of DataStore's average, not averages ***

  The obvious implementation - add up the sixteen slots and divide - would put
  a second, independently-derived number right next to DataStore's, and any
  disagreement between them reads as a bug. DataStore's GetAverageItemLevel is
  whatever Blizzard's own GetAverageItemLevel() said at the last scan, and
  Blizzard's rules for it are not fully reproducible from the outside (how a
  two-hander with an empty offhand is counted, for one).

  So both numbers are computed as `DataStore's average + gain / 16`, where
  `gain` only ever counts slots an unequipped item actually improves. That
  makes "carries nothing useful" render *exactly* equal to the equipped
  average, and keeps the three columns from ever inverting.

  The divisor and the treatment of empty slots are not guesses: across the 22
  characters in this account's DataStore_Inventory snapshot, every stored
  averageItemLvl is an exact multiple of 1/16, including on characters with
  several empty slots - so sixteen slots, empty ones contributing zero.

  *** One latent hazard in the equipped-slot data ***

  DataStore_Inventory's ScanInventorySlot only stores a full item link when
  IsEnchanted(link) matches; otherwise it stores a bare itemID, and
  C_Item.GetDetailedItemLevelInfo on a bare itemID answers with the item's
  *base* item level, no bonus-ID upgrade track applied. That would understate
  an equipped slot and so overstate the gain against it. In practice it does
  not currently bite: IsEnchanted's pattern does not match the modern link
  format, and all 352 stored equipment slots in this account are full links,
  zero bare itemIDs. It is documented here (and in docs/DATA_SOURCES.md)
  because it is a live code path that a link-format change could reactivate.

  Two further deliberate approximations, both documented rather than fixed:
  two-handers are treated as occupying the main hand only (equipping one does
  not empty the offhand here), and level requirements are ignored entirely -
  that is the whole point of the "max" column.

----------------------------------------------------------------------------]]--

WarbandMeDowns.ItemLevel = WarbandMeDowns.ItemLevel or {}
local ItemLevel = WarbandMeDowns.ItemLevel
local Data = WarbandMeDowns.Data
local Characters = WarbandMeDowns.Characters

-- The slots that count toward an average equipped item level. Note this is
-- deliberately NOT every key in Data.EquipLocToSlotID: the shirt
-- (INVSLOT_BODY) and tabard (INVSLOT_TABARD) are equipment but never count
-- toward an item level average, and INVSLOT_RANGED is vestigial in retail
-- (bows and guns equip to the main hand).
local AiLSlots = {
    INVSLOT_HEAD,
    INVSLOT_NECK,
    INVSLOT_SHOULDER,
    INVSLOT_CHEST,
    INVSLOT_WAIST,
    INVSLOT_LEGS,
    INVSLOT_FEET,
    INVSLOT_WRIST,
    INVSLOT_HAND,
    INVSLOT_FINGER1,
    INVSLOT_FINGER2,
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
    INVSLOT_BACK,
    INVSLOT_MAINHAND,
    INVSLOT_OFFHAND,
}

local AiLSlotCount = #AiLSlots

-- Equip locations that can land in more than one slot, mirroring exactly the
-- special cases WarbandMeDowns.Characters.GetEquippedItemsForEquipLocation
-- already makes. Everything else resolves through Data.EquipLocToSlotID.
local MultiSlotEquipLocations = {
    INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
    INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
    INVTYPE_WEAPON = { INVSLOT_MAINHAND, INVSLOT_OFFHAND },
}

---@class WarbandMeDownsProjectedItemLevels
---@field maxItemLevel number? # equipping everything they already carry
---@field theoreticalItemLevel number? # ...plus what the engine would send them
---@field unresolved boolean # some item involved could not be read yet

-- *** Reading what a character is wearing

---The item currently in one of a character's equipment slots.
---
---For the logged-in character this goes to the live API, which is both fresher
---than DataStore's snapshot (which lags an equipment change until its next
---scan) and immune to the bare-itemID hazard in the file header. Doing this
---only for the current character does not reintroduce a "depends on who is
---logged in" problem: these two numbers are display-only and never feed back
---into an assignment.
---@param character string
---@param slotId number
---@return ItemInfo?
local function GetEquippedLink(character, slotId)
    if character == DataStore.ThisCharKey and type(GetInventoryItemLink) == "function" then
        local success, link = pcall(GetInventoryItemLink, "player", slotId)
        if success and link then
            return link
        end
    end

    return DataStore:GetInventoryItem(character, slotId)
end

---What the character has in every item-level-relevant slot right now.
---
---An empty slot is 0 - a real, known "nothing here". An item that is present
---but not cached yet is NOT 0: it stays at whatever it is and is reported as
---unresolved instead, so a cold cache can never make a fully geared alt look
---naked (the same rule Data.GetActualItemLevel documents).
---@param character string
---@return table<number, number> slotItemLevels # keyed by inventory slot id
---@return boolean unresolved
local function ReadEquippedItemLevels(character)
    local slotItemLevels = {}
    local unresolved = false

    for _, slotId in ipairs(AiLSlots) do
        local link = GetEquippedLink(character, slotId)
        if not link then
            slotItemLevels[slotId] = 0
        else
            local itemLevel = Data.GetActualItemLevel(link)
            if itemLevel then
                slotItemLevels[slotId] = itemLevel
            else
                -- Present but unreadable: block this slot from being "improved"
                -- by pretending it is worth more than anything can beat.
                slotItemLevels[slotId] = math.huge
                unresolved = true
            end
        end
    end

    return slotItemLevels, unresolved
end

-- *** Candidates

---Every slot an item worn at this equip location could occupy, restricted to
---the slots that count toward the average.
---@param equipLocation string?
---@return number[]?
local function CandidateSlotsFor(equipLocation)
    if not equipLocation or equipLocation == "" then
        return nil
    end

    local multi = MultiSlotEquipLocations[equipLocation]
    if multi then
        return multi
    end

    local slotId = Data.EquipLocToSlotID[equipLocation]
    if not slotId then
        return nil
    end

    for _, aiLSlotId in ipairs(AiLSlots) do
        if aiLSlotId == slotId then
            return { slotId }
        end
    end

    -- A shirt, a tabard, or the vestigial ranged slot: real equipment, but it
    -- never moves an item level average.
    return nil
end

---Turns raw entries into the shape the fill below wants: item level, the
---slots it could go in, and nothing else. Items this character could never
---wear (wrong armor class, a weapon their spec does not favor) and items that
---cannot move an average are dropped here.
---@param character string
---@param entries table[] # Assignment pool/floorExtra entries
---@return table[] candidates # { itemLevel, slots }
---@return boolean unresolved
local function BuildCandidates(character, entries)
    local candidates = {}
    local unresolved = false

    for _, entry in ipairs(entries) do
        local itemLevel = Data.GetActualItemLevel(entry.link)
        local equipLocation = Data.GetItemEquipLocation(entry.link)

        if not itemLevel or not equipLocation then
            unresolved = true
        else
            local slots = CandidateSlotsFor(equipLocation)
            local classID, subclassID = Data.GetItemClassAndSubclass(entry.link)

            if slots and classID and subclassID
                and Characters.CanCharacterEquipItemClass(character, classID, subclassID) then
                table.insert(candidates, {
                    itemLevel = itemLevel,
                    slots = slots,
                    link = entry.link,
                })
            end
        end
    end

    -- Best first, so the greedy fill below is optimal for independent slots:
    -- once an item is placed, nothing left can want that slot more. The link
    -- tiebreak keeps two equal-item-level candidates in a stable order.
    table.sort(candidates, function(left, right)
        if left.itemLevel ~= right.itemLevel then
            return left.itemLevel > right.itemLevel
        end
        return tostring(left.link) < tostring(right.link)
    end)

    return candidates, unresolved
end

-- *** Projection

---Total item level gained by equipping the best of `entries` into the slots
---they fit, on top of what the character is already wearing. Never negative:
---an item only ever goes in if it beats what is there.
---@param character string
---@param slotItemLevels table<number, number>
---@param entries table[]
---@return number gain
---@return boolean unresolved
local function ProjectGain(character, slotItemLevels, entries)
    local candidates, unresolved = BuildCandidates(character, entries)

    -- Work on a copy: the caller runs this twice against the same equipped
    -- baseline, once for "max" and once for "theoretical".
    local projected = {}
    for slotId, itemLevel in pairs(slotItemLevels) do
        projected[slotId] = itemLevel
    end

    local gain = 0

    for _, candidate in ipairs(candidates) do
        local weakestSlot, weakestItemLevel = nil, nil
        for _, slotId in ipairs(candidate.slots) do
            local current = projected[slotId]
            if current and (not weakestItemLevel or current < weakestItemLevel) then
                weakestSlot, weakestItemLevel = slotId, current
            end
        end

        if weakestSlot and candidate.itemLevel > weakestItemLevel then
            gain = gain + (candidate.itemLevel - weakestItemLevel)
            projected[weakestSlot] = candidate.itemLevel
        end
    end

    return gain, unresolved
end

---Both projected averages for one character.
---@param character string
---@param ownedEntries table[] # everything in their own bags, bank and mail
---@param incomingEntries table[] # what the engine claimed for them from elsewhere
---@return WarbandMeDownsProjectedItemLevels
local function ProjectForCharacter(character, ownedEntries, incomingEntries)
    local averageItemLevel = DataStore:GetAverageItemLevel(character)
    if not averageItemLevel or averageItemLevel <= 0 then
        return { unresolved = false }
    end

    local slotItemLevels, unresolved = ReadEquippedItemLevels(character)

    local maxGain, maxUnresolved = ProjectGain(character, slotItemLevels, ownedEntries)

    local combined = {}
    for _, entry in ipairs(ownedEntries) do
        table.insert(combined, entry)
    end
    for _, entry in ipairs(incomingEntries) do
        table.insert(combined, entry)
    end
    local theoreticalGain, theoreticalUnresolved = ProjectGain(character, slotItemLevels, combined)

    return {
        maxItemLevel = averageItemLevel + maxGain / AiLSlotCount,
        theoreticalItemLevel = averageItemLevel + theoreticalGain / AiLSlotCount,
        unresolved = unresolved or maxUnresolved or theoreticalUnresolved
            or WarbandMeDowns.Assignment:HasUnreadableItems(character),
    }
end

-- *** Entry point

---Projected item levels for the whole warband, keyed by character.
---
---Deliberately one call for the entire table rather than one per row: the
---engine only has to be brought up to date and fully settled once, and the
---pool is walked once instead of once per character.
---@return table<string, WarbandMeDownsProjectedItemLevels>
function ItemLevel.GetProjectedItemLevelsForWarband()
    local Assignment = WarbandMeDowns.Assignment

    Assignment:EnsureFresh()
    -- entry.claimedBy is only filled in for groups that have been settled, and
    -- settlement is lazy - so without this every "theoretical" number would
    -- silently depend on which tooltips the player happened to hover.
    Assignment:SettleAllGroups()

    local owned = {}
    local incoming = {}

    Assignment:IterateOwnedEntries(function(entry)
        owned[entry.character] = owned[entry.character] or {}
        table.insert(owned[entry.character], entry)

        -- An item the engine assigned to the character who already owns it is
        -- not incoming: it is already counted above, and counting it twice
        -- would let one physical ring fill both ring slots.
        if entry.claimedBy and entry.claimedBy ~= entry.character then
            incoming[entry.claimedBy] = incoming[entry.claimedBy] or {}
            table.insert(incoming[entry.claimedBy], entry)
        end
    end)

    local projections = {}
    for _, character in ipairs(Characters.GetWarbandCharacters()) do
        projections[character] = ProjectForCharacter(
            character,
            owned[character] or {},
            incoming[character] or {}
        )
    end

    return projections
end
