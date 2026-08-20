--[[----------------------------------------------------------------------------

  HandMeDowns/Assignment.lua
  The global warband assignment engine.

  Instead of answering "is this hovered item an upgrade?" from scratch on
  every tooltip, this precomputes, per warband character and per equipment
  slot, which item they should end up with - considering every equipped,
  bagged, banked, and mailed item across the whole warband at once, so a
  spare in one character's bag can cascade down to a lower-priority
  character instead of being invisible to the recommendation. See
  HandMeDowns.lua for the license header covering the whole addon.

  Every item instance in the warband falls into exactly one bucket, decided
  once per recompute in ScanWarband:
    1. Equipped (any bind type) - always a floor a candidate must beat for
       that character/slot. Never reassigned to anyone else.
    2. Bag/bank/mail, NOT sendable to a twink (soulbound) - also a floor
       (matches the old GetBestCompareItem, which ignored bind type), but
       can never be claimed by another character.
    3. Bag/bank/mail, sendable to a twink - the only items ever reassigned;
       up for grabs by any eligible character in the warband, including
       their current owner.

  The expensive part (the full warband scan) happens once per recompute.
  Settling any one (slot-class, target equip location) pair is lazy and
  memoized for the current generation, so hovering many items that all
  share a slot-class (e.g. browsing a vendor's rings) only ever pays for
  that settlement once.

----------------------------------------------------------------------------]]--

HandMeDowns.Assignment = HandMeDowns.Assignment or {}
local Assignment = HandMeDowns.Assignment
local Data = HandMeDowns.Data
local Characters = HandMeDowns.Characters
local Pawn = HandMeDowns.Pawn

-- Sentinels, mirroring the old CacheMiss idiom.
Assignment.Sell = {}         -- confirmed upgrade for nobody: drives the tooltip's sell line
Assignment.Ineligible = {}   -- this character can never use this slot-class at all

-- Per-generation state, wiped wholesale by Recompute()/Reset() - see below.
Assignment.dirty = true
Assignment.pool = {}             -- pool[slotClassKey][rawEquipLoc] = { entry, ... }          (sendable bag/bank/mail items)
Assignment.floorExtra = {}       -- floorExtra[slotClassKey][rawEquipLoc] = { entry, ... }     (unsendable bag/bank/mail items)
Assignment.entryByLink = {}      -- entryByLink[itemLink] = entry                              (first pool entry seen for a link)
Assignment.settledBestCache = {} -- settledBestCache[slotClassKey][targetEquipLoc][character] = itemLink | false | Ineligible
Assignment._sortedCharacters = {}
Assignment._debounceToken = 0

---Compares two items of the same slot-class for a character: Pawn's score
---first, when Pawn is installed and a scale resolves for the character,
---falling back to plain item level only when Pawn has no opinion (not
---installed, unknown spec, or unable to score one of these two particular
---items). This is the single comparator used everywhere "which of these
---two items is better for this character" is decided. Either item may be
---nil/false (an empty slot).
---@param character string
---@param itemLinkA ItemInfo
---@param itemLinkB ItemInfo
---@return integer # 1 if A is preferred, -1 if B is preferred, 0 if tied
function Assignment.CompareItemsForCharacter(character, itemLinkA, itemLinkB)
    local scaleName = Pawn.GetPawnScaleNameForCharacter(character)
    if scaleName then
        local pawnResult = Pawn.CompareItemValuesForScale(itemLinkA, itemLinkB, scaleName)
        if pawnResult then
            return pawnResult
        end
    end

    local levelA = (itemLinkA and Data.GetActualItemLevel(itemLinkA)) or 0
    local levelB = (itemLinkB and Data.GetActualItemLevel(itemLinkB)) or 0
    if levelA ~= levelB then
        return levelA > levelB and 1 or -1
    end

    return 0
end

-- *** Phase A: single full pass over every character's bag/bank/mail items

local WarnedMissingMailAPI = false

---Buckets one bag/bank/mail item into the pool (sendable) or floorExtra
---(unsendable) table for its slot-class, keyed by its own equip location.
---@param character string
---@param itemLink ItemInfo?
function Assignment:_ClassifyItem(character, itemLink)
    if not itemLink then
        return
    end

    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    if classID ~= Data.ItemClassArmor and classID ~= Data.ItemClassWeapon then
        return
    end

    local equipLoc = Data.GetItemEquipLocation(itemLink)
    if not equipLoc or equipLoc == "" then
        return
    end

    local bind = Data.GetItemBind(itemLink)
    local sendable = bind and Data.CanItemBeSentToTwink(bind)

    local slotClassKey = Data.SlotClassKey(classID, subclassID)
    local entry = { link = itemLink, character = character }

    local bucketTable = sendable and self.pool or self.floorExtra
    bucketTable[slotClassKey] = bucketTable[slotClassKey] or {}
    bucketTable[slotClassKey][equipLoc] = bucketTable[slotClassKey][equipLoc] or {}
    table.insert(bucketTable[slotClassKey][equipLoc], entry)

    if sendable and not self.entryByLink[itemLink] then
        self.entryByLink[itemLink] = entry
    end
end

---One pass over every character's bags, bank, and mail. Equipped items are
---deliberately not scanned here: they're read on demand from DataStore (a
---handful of O(1) slot lookups) inside _BestFloorItem, since they're never
---reassignable and don't need bulk bucketing.
function Assignment:ScanWarband()
    self.pool = {}
    self.floorExtra = {}
    self.entryByLink = {}
    self.settledBestCache = {}

    for _, character in ipairs(Characters.GetWarbandCharacters()) do
        Characters.IterateStoredContainerItems(character, function(_, _, _, _, itemLink)
            self:_ClassifyItem(character, itemLink)
        end)

        if DataStore.IterateMails then
            DataStore:IterateMails(character, function(_, _, mailItemLink)
                self:_ClassifyItem(character, mailItemLink)
            end)
        elseif not WarnedMissingMailAPI then
            WarnedMissingMailAPI = true
            --@alpha@
            HandMeDowns:Print("warn: DataStore.IterateMails not available.")
            --@end-alpha@
        end
    end
end

-- *** Phase C: lazy, memoized cascading assignment per (slot-class, target equip location)

---@param character string
---@param targetEquipLoc string
---@param slotClassKey string # only items sharing this slot-class count as the floor
---@param floorExtra table[] # unsendable bag/bank/mail entries relevant to this target
---@return ItemInfo?
function Assignment:_BestFloorItem(character, targetEquipLoc, slotClassKey, floorExtra)
    local best = nil

    -- GetEquippedItemsForEquipLocation resolves purely by inventory slot (e.g.
    -- both hands for INVTYPE_WEAPON, both offhand-slot types for
    -- INVTYPE_SHIELD/INVTYPE_HOLDABLE), so it can hand back an item of a
    -- completely different slot-class than the one being settled (a Sword
    -- sharing INVTYPE_WEAPON with an equipped Dagger, a Shield sharing
    -- INVSLOT_OFFHAND with an equipped Holdable, ...). Only count it toward
    -- the floor if it's actually the same slot-class - i.e. the equivalent of
    -- Data.AreComparableItemTypes, matching how pool/floorExtra are already
    -- bucketed.
    for _, equippedLink in ipairs(Characters.GetEquippedItemsForEquipLocation(character, targetEquipLoc)) do
        if equippedLink then
            local equippedClassID, equippedSubclassID = Data.GetItemClassAndSubclass(equippedLink)
            if Data.SlotClassKey(equippedClassID, equippedSubclassID) == slotClassKey then
                if not best or Assignment.CompareItemsForCharacter(character, equippedLink, best) == 1 then
                    best = equippedLink
                end
            end
        end
    end

    for _, entry in ipairs(floorExtra) do
        if entry.character == character and (not best or Assignment.CompareItemsForCharacter(character, entry.link, best) == 1) then
            best = entry.link
        end
    end

    return best
end

---Unions every pool/floorExtra bucket whose own equip location satisfies
---Data.EquipLocationsMatch(candidateLoc, targetEquipLoc) against targetEquipLoc -
---reusing that predicate exactly as-is, including its asymmetry.
---@param bucketsBySlotClass table
---@param slotClassKey string
---@param targetEquipLoc string
---@return table[]
local function UnionMatchingBuckets(bucketsBySlotClass, slotClassKey, targetEquipLoc)
    local result = {}
    local buckets = bucketsBySlotClass[slotClassKey]
    if not buckets then
        return result
    end

    for loc, entries in pairs(buckets) do
        if Data.EquipLocationsMatch(loc, targetEquipLoc) then
            for _, entry in ipairs(entries) do
                table.insert(result, entry)
            end
        end
    end

    return result
end

---Scans the whole unclaimed candidate pool for the single best entry that
---beats the character's floor, claiming it if found. Unlike a plain
---item-level ordering, a lower-ilvl entry can still win once Pawn score is
---authoritative (see Assignment.CompareItemsForCharacter), so this can't
---stop early the way an item-level-sorted scan could - it has to consider
---every unclaimed candidate. Correct despite comparing entries pairwise
---against a moving `best` rather than against `floor` every time, since the
---comparator is transitive: once `best` already beats `floor`, anything
---that beats `best` also beats `floor`.
---@param character string
---@param candidates table[]
---@param floor ItemInfo?
---@return table? claimedEntry
function Assignment:_ClaimBestCandidate(character, candidates, floor)
    local best = nil

    for _, entry in ipairs(candidates) do
        if not entry.claimedBy then
            local reference = best and best.link or floor
            if Assignment.CompareItemsForCharacter(character, entry.link, reference) == 1 then
                best = entry
            end
        end
    end

    return best
end

---Settles one (slot-class, target equip location) pair: walks the warband
---in priority order, greedily giving each eligible character the better of
---their own floor and the best still-unclaimed pool candidate. A claimed
---pool entry is removed from play for every other target group it could
---also have satisfied (e.g. an ambidextrous one-hander claimed while
---settling INVTYPE_WEAPON is no longer available when INVTYPE_WEAPONMAINHAND
---is settled later). No-ops if already settled this generation.
---@param slotClassKey string
---@param targetEquipLoc string
---@param classID number
---@param subclassID number
function Assignment:SettleGroup(slotClassKey, targetEquipLoc, classID, subclassID)
    self.settledBestCache[slotClassKey] = self.settledBestCache[slotClassKey] or {}
    if self.settledBestCache[slotClassKey][targetEquipLoc] then
        return
    end

    local candidates = UnionMatchingBuckets(self.pool, slotClassKey, targetEquipLoc)
    local floorExtra = UnionMatchingBuckets(self.floorExtra, slotClassKey, targetEquipLoc)

    local settledBest = {}
    for _, character in ipairs(self._sortedCharacters) do
        if not Characters.CanCharacterEquipItemClass(character, classID, subclassID) then
            settledBest[character] = self.Ineligible
        else
            local floor = self:_BestFloorItem(character, targetEquipLoc, slotClassKey, floorExtra)
            local claimed = self:_ClaimBestCandidate(character, candidates, floor)
            if claimed then
                claimed.claimedBy = character
                claimed.claimedOverFloor = floor
                settledBest[character] = claimed.link
            else
                settledBest[character] = floor or false
            end
        end
    end

    self.settledBestCache[slotClassKey][targetEquipLoc] = settledBest
end

-- *** Phase D: exposing results

---@param character string
---@param itemLink ItemInfo
---@param compareItem ItemInfo?
---@return [string, number, number, boolean] upgradeInfo character, compareItemLevel, itemLevel, statOnlyUpgrade
function Assignment:BuildUpgradeInfo(character, itemLink, compareItem)
    local itemLevel = Data.GetActualItemLevel(itemLink) or 0
    local compareItemLevel = (compareItem and Data.GetActualItemLevel(compareItem)) or 0
    -- Not a strict item-level increase: either an equal-ilvl stat-only pick,
    -- or - now that Pawn score can be authoritative - a lower-ilvl item Pawn
    -- prefers anyway. Tooltip.lua distinguishes the two by re-comparing
    -- itemLevel to compareItemLevel itself.
    local statOnlyUpgrade = itemLevel <= compareItemLevel
    return { character, compareItemLevel, itemLevel, statOnlyUpgrade }
end

---Finds the destination for a given item: the character who should keep or
---receive it, HandMeDowns.Assignment.Sell if it's confirmed to be an
---upgrade for nobody, or nil if it was never eligible to be sent to a twink
---at all (wrong bind type, not armor/weapon, or not equippable).
---
---Already-owned items resolve in O(1) once their slot-class/target group is
---settled. Items nobody in the warband owns yet (loot window, vendor,
---trade, chat links) fall back to an O(#characters) walk against each
---character's already-settled best - no warband rescan needed.
---@param itemLink ItemInfo
---@return string|table|nil
function Assignment:GetBestCharacterForItem(itemLink)
    local bind = Data.GetItemBind(itemLink)
    if not bind or not Data.CanItemBeSentToTwink(bind) then
        return nil
    end

    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    if classID ~= Data.ItemClassArmor and classID ~= Data.ItemClassWeapon then
        return nil
    end

    local targetEquipLoc = Data.GetItemEquipLocation(itemLink)
    if not targetEquipLoc or targetEquipLoc == "" then
        return nil
    end

    self:EnsureFresh()

    local slotClassKey = Data.SlotClassKey(classID, subclassID)
    self:SettleGroup(slotClassKey, targetEquipLoc, classID, subclassID)

    -- Owned path: this exact item was seen during the warband scan.
    local entry = self.entryByLink[itemLink]
    if entry then
        if entry.claimedBy then
            return self:BuildUpgradeInfo(entry.claimedBy, itemLink, entry.claimedOverFloor)
        end
        return self.Sell
    end

    -- Foreign path: not part of the precomputed pool - compare against every
    -- character's already-settled best instead of rescanning the warband.
    local settledBest = self.settledBestCache[slotClassKey][targetEquipLoc]
    for _, character in ipairs(self._sortedCharacters) do
        local best = settledBest[character]
        if best ~= self.Ineligible and Assignment.CompareItemsForCharacter(character, itemLink, best) == 1 then
            return self:BuildUpgradeInfo(character, itemLink, best)
        end
    end

    return self.Sell
end

-- *** Dirty-flag orchestration
--
-- Invalidation events mark the engine dirty and (re)arm a debounce instead
-- of eagerly recomputing - recomputing right after looting mid-combat is
-- exactly the wrong moment, since nobody's looking at a tooltip yet. Once
-- the debounce fires, an out-of-combat background recompute keeps the
-- engine warm; but correctness never depends on that firing; EnsureFresh()
-- always recomputes synchronously if still dirty, and is called before
-- every lookup.

function Assignment:EnsureFresh()
    if self.dirty then
        self:Recompute()
    end
end

function Assignment:Recompute()
    self:ScanWarband()
    self._sortedCharacters = Characters.GetSortedWarbandCharacters()
    Characters.ClearEligibilityCache()
    Characters.ClearSpecCache()
    Pawn.ClearCaches()
    self.dirty = false
end

---Marks the engine dirty and arms a debounced background recompute attempt.
---Safe to call repeatedly in a burst (e.g. several bag-update events in a
---row): only the most recently armed timer will actually try to recompute.
function Assignment:MarkDirty()
    self.dirty = true
    self._debounceToken = self._debounceToken + 1
    local token = self._debounceToken

    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            self:TryBackgroundRecompute(token)
        end)
    end
end

---@param token number
function Assignment:TryBackgroundRecompute(token)
    if token ~= self._debounceToken then
        return -- superseded by a newer invalidation
    end

    if not self.dirty then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return -- try again on the next debounce; EnsureFresh() is the guaranteed fallback
    end

    self:Recompute()
end

---Drops all engine state. Called on OnDisable so a re-enable starts clean.
function Assignment:Reset()
    self.pool = {}
    self.floorExtra = {}
    self.entryByLink = {}
    self.settledBestCache = {}
    self._sortedCharacters = {}
    self.dirty = true

    Characters.ClearEligibilityCache()
    Characters.ClearSpecCache()
    Pawn.ClearCaches()
end
