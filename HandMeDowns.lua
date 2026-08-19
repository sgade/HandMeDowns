--[[----------------------------------------------------------------------------

  HandMeDowns/HandMeDowns.lua
  Recommends twinks for warbound gear

  Copyright (c) 2025 Sören Gade

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.

----------------------------------------------------------------------------]]--

HandMeDowns = LibStub("AceAddon-3.0"):NewAddon("HandMeDowns", "AceConsole-3.0")

local TooltipRecommendationCache = {}
local CacheMiss = {}
local CacheInvalidationFrame

local function arrayContains(array, element)
    for _, value in ipairs(array) do
        if value == element then
            return true
        end
    end
    return false
end

---Merges table2 into table1.
---
---Source: https://www.tutorialspoint.com/lua/lua_merging_arrays.htm
---@generic T
---@param table1 T[]
---@param table2 T[]
---@return T[]
local function tableConcat(table1, table2)
    for i = 1, #table2 do
        table1[#table1+1] = table2[i]
    end
    return table1
end

local function clearTable(table)
    for key in pairs(table) do
        table[key] = nil
    end
end

local ItemClassArmor = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or LE_ITEM_CLASS_ARMOR or 4
local ItemClassWeapon = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or LE_ITEM_CLASS_WEAPON or 2

local ArmorSubclass = {
    Generic = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Generic) or LE_ITEM_ARMOR_GENERIC or 0,
    Cloth = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cloth) or LE_ITEM_ARMOR_CLOTH or 1,
    Leather = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Leather) or LE_ITEM_ARMOR_LEATHER or 2,
    Mail = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Mail) or LE_ITEM_ARMOR_MAIL or 3,
    Plate = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Plate) or LE_ITEM_ARMOR_PLATE or 4,
    Shield = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Shield) or LE_ITEM_ARMOR_SHIELD or 6,
}

local WeaponSubclass = {
    Axe = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Axe) or LE_ITEM_WEAPON_AXE1H or 0,
    Axe2H = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Axe2H) or LE_ITEM_WEAPON_AXE2H or 1,
    Bow = (Enum and Enum.ItemWeaponSubclass and (Enum.ItemWeaponSubclass.Bow or Enum.ItemWeaponSubclass.Bows)) or LE_ITEM_WEAPON_BOWS or 2,
    Gun = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Gun) or LE_ITEM_WEAPON_GUNS or 3,
    Mace = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Mace) or LE_ITEM_WEAPON_MACE1H or 4,
    Mace2H = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Mace2H) or LE_ITEM_WEAPON_MACE2H or 5,
    Polearm = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Polearm) or LE_ITEM_WEAPON_POLEARM or 6,
    Sword = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Sword) or LE_ITEM_WEAPON_SWORD1H or 7,
    Sword2H = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Sword2H) or LE_ITEM_WEAPON_SWORD2H or 8,
    Warglaive = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Warglaive) or LE_ITEM_WEAPON_WARGLAIVE or 9,
    Staff = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Staff) or LE_ITEM_WEAPON_STAFF or 10,
    Fist = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fist) or LE_ITEM_WEAPON_UNARMED or 13,
    Dagger = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Dagger) or LE_ITEM_WEAPON_DAGGER or 15,
    Crossbow = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow) or LE_ITEM_WEAPON_CROSSBOW or 18,
    Wand = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or LE_ITEM_WEAPON_WAND or 19,
    FishingPole = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.FishingPole) or LE_ITEM_WEAPON_FISHINGPOLE or 20,
}

local ArmorSubclassClasses = {}
local WeaponSubclassClasses = {}
local WarnedItemSubclasses = {}

local function SetArmorSubclassClasses(subclassID, classes)
    if subclassID then
        ArmorSubclassClasses[subclassID] = classes
    end
end

local function SetWeaponSubclassClasses(subclassID, classes)
    if subclassID then
        WeaponSubclassClasses[subclassID] = classes
    end
end

SetArmorSubclassClasses(ArmorSubclass.Cloth, {"PRIEST", "MAGE", "WARLOCK"})
SetArmorSubclassClasses(ArmorSubclass.Leather, {"ROGUE", "MONK", "DRUID", "DEMONHUNTER"})
SetArmorSubclassClasses(ArmorSubclass.Mail, {"HUNTER", "SHAMAN", "EVOKER"})
SetArmorSubclassClasses(ArmorSubclass.Plate, {"WARRIOR", "PALADIN", "DEATHKNIGHT"})
SetArmorSubclassClasses(ArmorSubclass.Shield, {"WARRIOR", "PALADIN", "SHAMAN"})
SetArmorSubclassClasses(ArmorSubclass.Generic, {"WARRIOR", "PALADIN", "DEATHKNIGHT", "HUNTER", "SHAMAN", "EVOKER", "ROGUE", "MONK", "DRUID", "DEMONHUNTER", "PRIEST", "MAGE", "WARLOCK"})

SetWeaponSubclassClasses(WeaponSubclass.Axe, {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "SHAMAN", "MONK", "DEMONHUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Axe2H, {"WARRIOR", "PALADIN", "HUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Bow, {"HUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Gun, {"HUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Mace, {"WARRIOR", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "MONK", "DRUID", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Mace2H, {"WARRIOR", "PALADIN", "DRUID", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Polearm, {"WARRIOR", "PALADIN", "HUNTER", "MONK", "DRUID", "DEATHKNIGHT"})
SetWeaponSubclassClasses(WeaponSubclass.Sword, {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "MONK", "MAGE", "WARLOCK", "DEMONHUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Sword2H, {"WARRIOR", "PALADIN", "HUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Warglaive, {"DEMONHUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Staff, {"WARRIOR", "HUNTER", "SHAMAN", "MONK", "DRUID", "PRIEST", "MAGE", "WARLOCK", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Fist, {"WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Dagger, {"WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID", "PRIEST", "MAGE", "WARLOCK", "DEMONHUNTER", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Crossbow, {"HUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Wand, {"PRIEST", "MAGE", "WARLOCK"})
SetWeaponSubclassClasses(WeaponSubclass.FishingPole, {"WARRIOR", "PALADIN", "DEATHKNIGHT", "HUNTER", "SHAMAN", "EVOKER", "ROGUE", "MONK", "DRUID", "DEMONHUNTER", "PRIEST", "MAGE", "WARLOCK"})

-- Specialization-level weapon/shield preferences.
--
-- These narrow the class-level tables above: the class-level tables answer
-- "could this class ever equip this?", these answer "would this spec ever want it?".
-- Every subclass listed here must also appear in that class' entry above,
-- because the class-level check always runs first.
local SpecsByClass = {}
local SpecClass = {}
local SpecWeaponSubclasses = {}
local SpecUsesShield = {}
local ClassFavoriteWeaponSubclasses = {}
local ClassUsesShield = {}

local function SetClassSpecs(class, specIDs)
    SpecsByClass[class] = specIDs
end

local function SetSpecWeaponSubclasses(specID, subclassIDs)
    if not specID then
        return
    end

    local subclasses = {}
    for _, subclassID in ipairs(subclassIDs) do
        subclasses[subclassID] = true
    end
    SpecWeaponSubclasses[specID] = subclasses
end

local function SetSpecUsesShield(specID)
    if not specID then
        return
    end

    SpecUsesShield[specID] = true
end

-- Well-known, stable, locale-independent Blizzard specialization IDs.
local Spec = {
    Arms = 71, Fury = 72, ProtectionWarrior = 73,
    HolyPaladin = 65, ProtectionPaladin = 66, Retribution = 70,
    BeastMastery = 253, Marksmanship = 254, Survival = 255,
    Assassination = 259, Outlaw = 260, Subtlety = 261,
    Discipline = 256, HolyPriest = 257, Shadow = 258,
    Blood = 250, FrostDeathKnight = 251, Unholy = 252,
    Elemental = 262, Enhancement = 263, RestorationShaman = 264,
    Arcane = 62, Fire = 63, FrostMage = 64,
    Affliction = 265, Demonology = 266, Destruction = 267,
    Brewmaster = 268, Windwalker = 269, Mistweaver = 270,
    Balance = 102, Feral = 103, Guardian = 104, RestorationDruid = 105,
    Havoc = 577, Vengeance = 581, Devourer = 1480,
    Devastation = 1467, Preservation = 1468, Augmentation = 1473,
}

SetClassSpecs("WARRIOR",     {Spec.Arms, Spec.Fury, Spec.ProtectionWarrior})
SetClassSpecs("PALADIN",     {Spec.HolyPaladin, Spec.ProtectionPaladin, Spec.Retribution})
SetClassSpecs("HUNTER",      {Spec.BeastMastery, Spec.Marksmanship, Spec.Survival})
SetClassSpecs("ROGUE",       {Spec.Assassination, Spec.Outlaw, Spec.Subtlety})
SetClassSpecs("PRIEST",      {Spec.Discipline, Spec.HolyPriest, Spec.Shadow})
SetClassSpecs("DEATHKNIGHT", {Spec.Blood, Spec.FrostDeathKnight, Spec.Unholy})
SetClassSpecs("SHAMAN",      {Spec.Elemental, Spec.Enhancement, Spec.RestorationShaman})
SetClassSpecs("MAGE",        {Spec.Arcane, Spec.Fire, Spec.FrostMage})
SetClassSpecs("WARLOCK",     {Spec.Affliction, Spec.Demonology, Spec.Destruction})
SetClassSpecs("MONK",        {Spec.Brewmaster, Spec.Windwalker, Spec.Mistweaver})
SetClassSpecs("DRUID",       {Spec.Balance, Spec.Feral, Spec.Guardian, Spec.RestorationDruid})
SetClassSpecs("DEMONHUNTER", {Spec.Havoc, Spec.Vengeance, Spec.Devourer})
SetClassSpecs("EVOKER",      {Spec.Devastation, Spec.Preservation, Spec.Augmentation})

-- Per-spec favored weapon subclasses / shield usage.
--
-- Source: Blizzard's own ChrSpecialization game-data table, Description_lang
-- field ("Preferred Weapon(s): ..."), queried from the wago.tools DB2 export
-- (https://wago.tools/db2/ChrSpecialization) on 2026-08-18 against live WoW
-- patch 12.1 ("Midnight") data - including Devourer (id 1480), the new third
-- Demon Hunter spec added in Midnight.
--
-- To refresh this table later, re-fetch that same export (or the equivalent
-- DBC/DB2 dump from wowhead/wago after a future patch) and re-read each spec
-- row's Description_lang "Preferred Weapon" clause - the mapping from that
-- text to WeaponSubclass/ArmorSubclass constants is mechanical: "Two-Handed
-- X" -> X2H, a bare weapon name -> its 1H constant, "Shield" ->
-- ArmorSubclass.Shield, and inherently-2H types (Staff/Polearm/Bow/Gun/
-- Crossbow/Warglaive) map directly since WeaponSubclass only carries one
-- entry for each of those. Every entry below was cross-checked against the
-- class-level WeaponSubclassClasses/ArmorSubclassClasses tables above so
-- nothing here is ever unreachable.
--
-- A few entries deliberately go beyond the official text, flagged inline:
-- Outlaw's Dagger (current guides mandate one in the off-hand for a spec
-- mechanic) and Windwalker's Polearm/Staff (a balance change made
-- two-handed weapons this season's top pick, ahead of the flavor text).
--
-- See docs/DATA_SOURCES.md for the full refresh method.

-- Warrior - "Two-Handed Axe, Mace, Sword" / "Dual Two-Handed Axes, Maces, Swords" / "Axe, Mace, Sword, and Shield"
SetSpecWeaponSubclasses(Spec.Arms,              {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})
SetSpecWeaponSubclasses(Spec.Fury,              {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})
SetSpecWeaponSubclasses(Spec.ProtectionWarrior, {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword})

-- Paladin - "Sword, Mace, and Shield" / "Sword, Mace, Axe, and Shield" / "Two-Handed Sword, Mace, Axe"
SetSpecWeaponSubclasses(Spec.HolyPaladin,       {WeaponSubclass.Sword, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.ProtectionPaladin, {WeaponSubclass.Sword, WeaponSubclass.Mace, WeaponSubclass.Axe})
SetSpecWeaponSubclasses(Spec.Retribution,       {WeaponSubclass.Sword2H, WeaponSubclass.Mace2H, WeaponSubclass.Axe2H})

-- Hunter - "Bow, Crossbow, Gun" (x2) / "Polearm, Staff, Axe, Dagger, Sword"
SetSpecWeaponSubclasses(Spec.BeastMastery,      {WeaponSubclass.Bow, WeaponSubclass.Crossbow, WeaponSubclass.Gun})
SetSpecWeaponSubclasses(Spec.Marksmanship,      {WeaponSubclass.Bow, WeaponSubclass.Crossbow, WeaponSubclass.Gun})
SetSpecWeaponSubclasses(Spec.Survival,          {WeaponSubclass.Polearm, WeaponSubclass.Staff, WeaponSubclass.Axe, WeaponSubclass.Dagger, WeaponSubclass.Sword})

-- Rogue - "Daggers" / "Axes, Maces, Swords, Fist Weapons" / "Daggers"
SetSpecWeaponSubclasses(Spec.Assassination,     {WeaponSubclass.Dagger})
SetSpecWeaponSubclasses(Spec.Outlaw,            {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword, WeaponSubclass.Fist, WeaponSubclass.Dagger})
SetSpecWeaponSubclasses(Spec.Subtlety,          {WeaponSubclass.Dagger})

-- Priest - "Staff, Wand, Dagger, Mace" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Discipline,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.HolyPriest,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Shadow,            {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Mace})

-- Death Knight - "Two-Handed Axe, Mace, Sword" / "Dual Axes, Maces, Swords" / "Two-Handed Axe, Mace, Sword"
SetSpecWeaponSubclasses(Spec.Blood,             {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})
SetSpecWeaponSubclasses(Spec.FrostDeathKnight,  {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Unholy,            {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})

-- Shaman - "Mace, Dagger, and Shield" / "Dual Axes, Maces, Fist Weapons" / "Mace, Dagger, and Shield"
SetSpecWeaponSubclasses(Spec.Elemental,         {WeaponSubclass.Mace, WeaponSubclass.Dagger})
SetSpecWeaponSubclasses(Spec.Enhancement,       {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Fist})
SetSpecWeaponSubclasses(Spec.RestorationShaman, {WeaponSubclass.Mace, WeaponSubclass.Dagger})

-- Mage - "Staff, Wand, Dagger, Sword" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Arcane,            {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Fire,              {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.FrostMage,         {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})

-- Warlock - "Staff, Wand, Dagger, Sword" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Affliction,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Demonology,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Destruction,       {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})

-- Monk - "Staff, Polearm" / "Fist Weapons, Axes, Maces, Swords" / "Staff, Mace, Sword"
SetSpecWeaponSubclasses(Spec.Brewmaster,        {WeaponSubclass.Staff, WeaponSubclass.Polearm})
SetSpecWeaponSubclasses(Spec.Windwalker,        {WeaponSubclass.Fist, WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword, WeaponSubclass.Polearm, WeaponSubclass.Staff})
SetSpecWeaponSubclasses(Spec.Mistweaver,        {WeaponSubclass.Staff, WeaponSubclass.Mace, WeaponSubclass.Sword})

-- Druid - "Staff, Dagger, Mace" / "Staff, Polearm" / "Staff, Polearm" / "Staff, Dagger, Mace"
SetSpecWeaponSubclasses(Spec.Balance,           {WeaponSubclass.Staff, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Feral,             {WeaponSubclass.Staff, WeaponSubclass.Polearm})
SetSpecWeaponSubclasses(Spec.Guardian,          {WeaponSubclass.Staff, WeaponSubclass.Polearm})
SetSpecWeaponSubclasses(Spec.RestorationDruid,  {WeaponSubclass.Staff, WeaponSubclass.Dagger, WeaponSubclass.Mace})

-- Demon Hunter - "Warglaives, Swords, Axes, Fist Weapons" (x2) / "Warglaives, Swords, Axes, Fist Weapons, Daggers"
SetSpecWeaponSubclasses(Spec.Havoc,             {WeaponSubclass.Warglaive, WeaponSubclass.Sword, WeaponSubclass.Axe, WeaponSubclass.Fist})
SetSpecWeaponSubclasses(Spec.Vengeance,         {WeaponSubclass.Warglaive, WeaponSubclass.Sword, WeaponSubclass.Axe, WeaponSubclass.Fist})
SetSpecWeaponSubclasses(Spec.Devourer,          {WeaponSubclass.Warglaive, WeaponSubclass.Sword, WeaponSubclass.Axe, WeaponSubclass.Fist, WeaponSubclass.Dagger})

-- Evoker - "Staff, Sword, Dagger, Mace" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Devastation,       {WeaponSubclass.Staff, WeaponSubclass.Sword, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Preservation,      {WeaponSubclass.Staff, WeaponSubclass.Sword, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Augmentation,      {WeaponSubclass.Staff, WeaponSubclass.Sword, WeaponSubclass.Dagger, WeaponSubclass.Mace})

SetSpecUsesShield(Spec.ProtectionWarrior)
SetSpecUsesShield(Spec.HolyPaladin)
SetSpecUsesShield(Spec.ProtectionPaladin)
SetSpecUsesShield(Spec.Elemental)
SetSpecUsesShield(Spec.RestorationShaman)

-- Union of every spec's preferences, used when a character's spec is unknown.
for class, specIDs in pairs(SpecsByClass) do
    local weaponSubclasses = {}
    local usesShield = false

    for _, specID in ipairs(specIDs) do
        SpecClass[specID] = class

        for subclassID in pairs(SpecWeaponSubclasses[specID] or {}) do
            weaponSubclasses[subclassID] = true
        end

        if SpecUsesShield[specID] then
            usesShield = true
        end
    end

    ClassFavoriteWeaponSubclasses[class] = weaponSubclasses
    ClassUsesShield[class] = usesShield
end

-- Numeric class IDs, Blizzard-stable, used only to talk to Pawn (see
-- GetPawnScaleNameForCharacter below) - Pawn's scale-lookup functions take
-- these instead of the classFile strings DataStore uses.
local ClassID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10,
    DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

---@param link ItemInfo
---@return Enum.ItemBind bindType
local function GetItemBind(link)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(link)
    return bindType
end

---@param link ItemInfo
local function GetItemClassAndSubclass(link)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    return classID, subclassID
end

local function AreComparableItemTypes(itemLink, compareItemLink)
    local itemClassID, itemSubclassID = GetItemClassAndSubclass(itemLink)
    local compareItemClassID, compareItemSubclassID = GetItemClassAndSubclass(compareItemLink)

    if itemClassID ~= compareItemClassID then
        return false
    end

    if itemClassID == ItemClassWeapon then
        return itemSubclassID == compareItemSubclassID
    end

    return true
end

---@param link ItemInfo
---@return number
local function GetActualItemLevel(link)
    local level, _, _ = C_Item.GetDetailedItemLevelInfo(link)
    return level
end

local WarnedMissingSpecAPI = false
local KnownSpecIDCache = {}
local SpecUnknown = {}

---Resolves the active specialization of a character, if known.
---Requires the optional DataStore_Talents module and a character that has
---been scanned at least once; returns `nil` otherwise, which callers must
---treat as "spec unknown", never as "cannot use anything".
---@param character string
---@return number? specID
local function GetKnownSpecID(character)
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
            HandMeDowns:Print("warn: DataStore.GetActiveSpecInfo not available.")
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

-- *** Secondary stat tie-breaking via Pawn (optional dependency)
--
-- HandMeDowns does not maintain its own secondary stat priorities. Instead,
-- when the Pawn addon (https://github.com/VgerMods/Pawn) is installed, its
-- own item-scoring calculation is used to break an exact item-level tie
-- between two comparable items. Pawn is not a required dependency, and its
-- functions are not a documented/versioned API - every call below is
-- defensive (existence and type checks, pcall) and degrades silently to
-- "no opinion" (the same fallback as an unknown spec) if Pawn isn't
-- installed, is a different version than expected, or errors internally.
-- See docs/DATA_SOURCES.md for exactly which Pawn functions this relies on,
-- the Pawn version it was verified against, and how to re-verify them.

local PawnScaleNameCache = {}
local PawnScaleUnknown = {}

---Finds the local (1-4) spec index Pawn expects, matching Blizzard's
---GetSpecializationInfoForClassID convention. SpecsByClass is already
---ordered to match that convention (see SetClassSpecs above).
---@param class string
---@param specID number
---@return number?
local function GetPawnLocalSpecIndex(class, specID)
    local specIDs = SpecsByClass[class]
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
local function GetPawnScaleNameForCharacter(character)
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
        local classID = class and ClassID[class]
        local specID = GetKnownSpecID(character)
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

---Scores an item against a named Pawn scale, using Pawn's own item parsing
---and valuation. Never throws; returns nil for any reason a value couldn't
---be produced.
---@param itemLink ItemInfo
---@param scaleName string
---@return number?
local function GetPawnItemValue(itemLink, scaleName)
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
---CompareItemsForCharacter.
---@param character string
---@param itemLinkA ItemInfo
---@param itemLinkB ItemInfo
---@return integer # 1 if A is preferred, -1 if B is preferred, 0 if tied or unknown
local function CompareItemStatsForCharacter(character, itemLinkA, itemLinkB)
    local scaleName = GetPawnScaleNameForCharacter(character)
    if not scaleName then
        -- Pawn isn't installed/usable, or the spec is unknown: no opinion,
        -- leave the tie as-is rather than guessing.
        return 0
    end

    local valueA = GetPawnItemValue(itemLinkA, scaleName)
    local valueB = GetPawnItemValue(itemLinkB, scaleName)
    if not valueA or not valueB or valueA == valueB then
        return 0
    end

    return valueA > valueB and 1 or -1
end

---Compares two items of the same equip location for a character: item
---level first, falling back to CompareItemStatsForCharacter only on an
---exact item-level tie. This is the single comparator used everywhere
---"which of these two items is better for this character" is decided.
---@param character string
---@param itemLinkA ItemInfo
---@param itemLinkB ItemInfo
---@return integer # 1 if A is preferred, -1 if B is preferred, 0 if tied
local function CompareItemsForCharacter(character, itemLinkA, itemLinkB)
    local levelA = (itemLinkA and GetActualItemLevel(itemLinkA)) or 0
    local levelB = (itemLinkB and GetActualItemLevel(itemLinkB)) or 0

    if levelA ~= levelB then
        return levelA > levelB and 1 or -1
    end

    return CompareItemStatsForCharacter(character, itemLinkA, itemLinkB)
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
local function IsItemSubclassFavoredBySpec(character, class, itemClassID, itemSubclassID)
    if itemClassID == ItemClassWeapon and itemSubclassID == WeaponSubclass.FishingPole then
        return true
    end

    local isWeapon = itemClassID == ItemClassWeapon
    local isShield = itemClassID == ItemClassArmor and itemSubclassID == ArmorSubclass.Shield
    if not isWeapon and not isShield then
        return true
    end

    local specID = GetKnownSpecID(character)
    if specID and SpecClass[specID] == class then
        if isShield then
            return SpecUsesShield[specID] == true
        end
        return SpecWeaponSubclasses[specID][itemSubclassID] == true
    end

    if isShield then
        return ClassUsesShield[class] == true
    end

    local favorites = ClassFavoriteWeaponSubclasses[class]
    return favorites ~= nil and favorites[itemSubclassID] == true
end

---@param character string
---@param itemLink ItemInfo
---@return boolean
local function CanCharacterEquipItem(character, itemLink)
    local itemClassID, itemSubclassID = GetItemClassAndSubclass(itemLink)
    local classesThatCanUseItem = nil

    if itemClassID == ItemClassArmor then
        classesThatCanUseItem = ArmorSubclassClasses[itemSubclassID]
    elseif itemClassID == ItemClassWeapon then
        classesThatCanUseItem = WeaponSubclassClasses[itemSubclassID]
    else
        return false
    end

    if not classesThatCanUseItem then
        --@alpha@
        local warningKey = tostring(itemClassID) .. "." .. tostring(itemSubclassID)
        if not WarnedItemSubclasses[warningKey] then
            WarnedItemSubclasses[warningKey] = true
            HandMeDowns:Print("warn: unknown item subclass '" .. warningKey .. "'")
        end
        --@end-alpha@
        return false
    end

    local _, class = DataStore:GetCharacterClass(character)

    if not arrayContains(classesThatCanUseItem, class) then
        return false
    end

    return IsItemSubclassFavoredBySpec(character, class, itemClassID, itemSubclassID)
end

local function GetItemEquipLocation(link)
    local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfo(link)
    return itemEquipLoc
end

local OneHandWeaponEquipLocations = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
}

local function EquipLocationsMatch(candidateEquipLocation, targetEquipLocation)
    if candidateEquipLocation == targetEquipLocation then
        return true
    end

    if targetEquipLocation == "INVTYPE_WEAPON" then
        return OneHandWeaponEquipLocations[candidateEquipLocation]
    elseif targetEquipLocation == "INVTYPE_WEAPONMAINHAND" then
        return candidateEquipLocation == "INVTYPE_WEAPON"
    elseif targetEquipLocation == "INVTYPE_WEAPONOFFHAND" then
        return candidateEquipLocation == "INVTYPE_WEAPON"
    end

    return false
end

local EquipLocToSlotID = {
    INVTYPE_HEAD       = INVSLOT_HEAD,       -- 1
    INVTYPE_NECK       = INVSLOT_NECK,       -- 2
    INVTYPE_SHOULDER   = INVSLOT_SHOULDER,   -- 3
    INVTYPE_BODY       = INVSLOT_BODY,       -- 4 (shirt)
    INVTYPE_CHEST      = INVSLOT_CHEST,      -- 5
    INVTYPE_ROBE       = INVSLOT_CHEST,      -- 5
    INVTYPE_WAIST      = INVSLOT_WAIST,      -- 6
    INVTYPE_LEGS       = INVSLOT_LEGS,       -- 7
    INVTYPE_FEET       = INVSLOT_FEET,       -- 8
    INVTYPE_WRIST      = INVSLOT_WRIST,      -- 9
    INVTYPE_HAND       = INVSLOT_HAND,       -- 10
    INVTYPE_FINGER     = INVSLOT_FINGER1,    -- needs special handling
    INVTYPE_TRINKET    = INVSLOT_TRINKET1,   -- needs special handling
    INVTYPE_CLOAK      = INVSLOT_BACK,       -- 15
    INVTYPE_WEAPON     = INVSLOT_MAINHAND,   -- needs dual-wield handling
    INVTYPE_2HWEAPON   = INVSLOT_MAINHAND,
    INVTYPE_WEAPONMAINHAND = INVSLOT_MAINHAND,
    INVTYPE_WEAPONOFFHAND  = INVSLOT_OFFHAND,
    INVTYPE_SHIELD     = INVSLOT_OFFHAND,
    INVTYPE_HOLDABLE   = INVSLOT_OFFHAND,
    INVTYPE_RANGED     = INVSLOT_RANGED,
    INVTYPE_RANGEDRIGHT = INVSLOT_RANGED,
    INVTYPE_THROWN     = INVSLOT_RANGED,
    INVTYPE_RELIC      = INVSLOT_RANGED,
    INVTYPE_TABARD     = INVSLOT_TABARD,     -- 19
}

---@param character string
---@param equipLocation string
---@return ItemInfo[]
local function GetEquippedItemsForEquipLocation(character, equipLocation)
    local slotId = EquipLocToSlotID[equipLocation]
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

---@param bindType Enum.ItemBind
---@return boolean
local function CanItemBeSentToTwink(bindType)
    ---@type Enum.ItemBind[]
    local relevantForTwinks = {
        Enum.ItemBind.OnEquip,
        Enum.ItemBind.ToWoWAccount,
        Enum.ItemBind.ToBnetAccount,
        Enum.ItemBind.ToBnetAccountUntilEquipped
    }
    return arrayContains(relevantForTwinks, bindType)
end

-- Reimplementation from DataStore_Containers. DataStore_Containers stores both
-- bag and bank-like containers, depending on what has been scanned for a character.
local function IterateStoredContainerItems(character, callback)
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
local function CharacterServerAndNameFromKey(key)
    local _, server, name = strsplit(".", key)
    return server, name
end

-- *** Lifecyle

function HandMeDowns:OnInitialize()
    CacheInvalidationFrame = CreateFrame("Frame")
    CacheInvalidationFrame:SetScript("OnEvent", function()
        HandMeDowns:InvalidateRecommendationCache()
    end)
end

function HandMeDowns:OnEnable()
    HandMeDowns:HookItemTooltips()
    HandMeDowns:RegisterCacheInvalidationEvents()

    --@debug@
    HandMeDowns:Print("Ready.")
    --@end-debug@
end

function HandMeDowns:HookItemTooltips()
    if HandMeDowns.tooltipHooksRegistered then
        return
    end

    HandMeDowns.tooltipHooksRegistered = true

    local function onTooltipSetItem(frame, ...)
        local success, errorMessage = pcall(HandMeDowns.OnTooltipSetItem, HandMeDowns, frame, ...)
        if not success then
            HandMeDowns:Print("tooltip error: " .. tostring(errorMessage))
        end
    end

    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(frame, ...)
            if frame == GameTooltip and HandMeDowns:IsEnabled() then
                return onTooltipSetItem(frame, ...)
            end
        end)
    else
        -- legacy
        GameTooltip:HookScript('OnTooltipSetItem', function (...)
            onTooltipSetItem(GameTooltip, ...)
        end)
    end
end

function HandMeDowns:OnDisable()
    if CacheInvalidationFrame then
        CacheInvalidationFrame:UnregisterAllEvents()
    end

    HandMeDowns:ClearRecommendationCache()

    --@debug@
    HandMeDowns:Print("Disabled.")
    --@end-debug@
end

function HandMeDowns:RegisterCacheInvalidationEvents()
    if not CacheInvalidationFrame then
        return
    end

    local events = {
        "BAG_UPDATE_DELAYED",
        "BANKFRAME_CLOSED",
        "GET_ITEM_INFO_RECEIVED",
        "MAIL_CLOSED",
        "MAIL_INBOX_UPDATE",
        "MAIL_SEND_SUCCESS",
        "MAIL_SUCCESS",
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_LEVEL_UP",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYERBANKSLOTS_CHANGED",
        "PLAYERREAGENTBANKSLOTS_CHANGED",
    }

    for _, eventName in ipairs(events) do
        pcall(CacheInvalidationFrame.RegisterEvent, CacheInvalidationFrame, eventName)
    end
end

function HandMeDowns:ClearRecommendationCache()
    clearTable(TooltipRecommendationCache)
    clearTable(KnownSpecIDCache)
    clearTable(PawnScaleNameCache)
end

function HandMeDowns:InvalidateRecommendationCache()
    HandMeDowns:ClearRecommendationCache()

    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            HandMeDowns:ClearRecommendationCache()
        end)
    end
end

-- *** Setting the tooltip

---Hooks the tooltip
---@param frame GameTooltip
function HandMeDowns:OnTooltipSetItem(frame, ...)
    ---@type string, ItemInfo
    ---@diagnostic disable-next-line: assign-type-mismatch
    local _, itemLink = frame:GetItem()
    if not itemLink then
        return
    end

    local upgradeInfo = HandMeDowns:GetCachedBestCharacterForItem(itemLink)
    if not upgradeInfo then
        return
    end

    local distributionInfo = (function()
        if upgradeInfo[1] == DataStore.ThisCharKey then
            return "Use here!"
        else
            local characterServer, characterName = CharacterServerAndNameFromKey(upgradeInfo[1])
            return "HandMeDowns! Send this to " .. characterName .. "@" .. characterServer .. "."
        end
    end)()

    local upgradeDescription
    if upgradeInfo[4] then
        -- Same item level as what's already available, but better secondary
        -- stats for the character's spec.
        upgradeDescription = "Better secondary stats at item level " .. upgradeInfo[3] .. "."
    else
        upgradeDescription = "Upgrade from " .. upgradeInfo[2] .. " to " .. upgradeInfo[3] .. "."
    end

    frame:AddLine(distributionInfo .. " " .. upgradeDescription, 0, 0.75, 0.33, false)
end

-- *** Finding the best character for an item

---Finds the best character to wear a given item, using a data-lifetime cache.
---@param link ItemInfo
---@return [string, number, number]? upgradeInfo
function HandMeDowns:GetCachedBestCharacterForItem(link)
    local cachedUpgradeInfo = TooltipRecommendationCache[link]
    if cachedUpgradeInfo == CacheMiss then
        return
    elseif cachedUpgradeInfo then
        return cachedUpgradeInfo
    end

    local upgradeInfo = HandMeDowns:FindBestCharacterForItem(link)
    TooltipRecommendationCache[link] = upgradeInfo or CacheMiss
    return upgradeInfo
end

---Finds the best character to wear a given item.
---
---Every character on the account - the current one included - is ranked by
---the same priority (current level first, then equipped average item
---level), then walked in that order; the first character the item is an
---upgrade for is the recommendation. This means the current character is
---not special-cased: if it happens to be first in priority order among the
---characters that need the item, it wins, exactly like an alt would.
---@param link ItemInfo
---@return [string, number, number, boolean]? upgradeInfo
function HandMeDowns:FindBestCharacterForItem(link)
    local bind = GetItemBind(link)
    if not bind then
        -- item cannot be equipped
        return
    end

    if not CanItemBeSentToTwink(bind) then
        -- item cannot be traded to twinks
        return
    end

    -- DataStore.ThisAccount: usually "Default"
    -- DataStore:GetCharacter(): usually "Default.Server.Name"
    -- assuming "this account" is the warband

    local characters = {}
    for realmName in pairs(DataStore:GetRealms(DataStore.ThisAccount)) do
        for _, character in pairs(DataStore:GetCharacters(realmName, DataStore.ThisAccount)) do
            table.insert(characters, character)
        end
    end

    table.sort(characters, function(left, right)
        local leftLevel = DataStore:GetCharacterLevel(left) or 0
        local rightLevel = DataStore:GetCharacterLevel(right) or 0
        if leftLevel ~= rightLevel then
            return leftLevel > rightLevel
        end

        local leftItemLevel = DataStore:GetAverageItemLevel(left) or 0
        local rightItemLevel = DataStore:GetAverageItemLevel(right) or 0
        return leftItemLevel > rightItemLevel
    end)

    for _, character in ipairs(characters) do
        local upgradeInfo = HandMeDowns:FindUpgradeForCharacter(link, character)
        if upgradeInfo then
            return upgradeInfo
        end
    end
end

---@param candidateItemLink ItemInfo
---@param targetItemLink ItemInfo
---@param character string
---@return boolean
local function IsComparableItemForCharacter(candidateItemLink, targetItemLink, character)
    if not candidateItemLink or not targetItemLink then
        return false
    end

    if not AreComparableItemTypes(targetItemLink, candidateItemLink) then
        return false
    end

    return CanCharacterEquipItem(character, candidateItemLink)
end

---Retrieves upgrade information about the given item for the character.
---If the item is an upgrade, upgrade info is returned, `nil` otherwise.
---
---An item counts as an upgrade either by item level, or - on an exact item
---level tie against the character's best comparable item - by secondary
---stats the character's spec favors more (see CompareItemsForCharacter).
---
---@param itemLink ItemInfo
---@param character string
---@return [string, number, number, boolean]? upgradeInfo character, compareItemLevel, itemLevel, statOnlyUpgrade
function HandMeDowns:FindUpgradeForCharacter(itemLink, character)
    if not character then
        return
    end

    if not CanCharacterEquipItem(character, itemLink) then
        return
    end

    local itemLevel = GetActualItemLevel(itemLink)
    if not itemLevel then
        -- comparison not possible
        return
    end

    local compareItem = HandMeDowns:GetBestCompareItem(itemLink, character)
    local compareItemLevel = (compareItem and GetActualItemLevel(compareItem)) or 0

    if CompareItemsForCharacter(character, itemLink, compareItem) ~= 1 then
        -- available item is equal or better than the one we compare for
        return
    end

    return {
        character,
        compareItemLevel,
        itemLevel,
        compareItemLevel == itemLevel
    }
end

---Finds the best available item as comparison for the given item: item
---level first, falling back to the character's spec-favored secondary
---stats only on an exact item-level tie (see CompareItemsForCharacter).
---
---@param itemLink ItemInfo The item to compare against.
---@param character string The character to search within.
---@return ItemInfo?
function HandMeDowns:GetBestCompareItem(itemLink, character)
    local equipmentLocation = GetItemEquipLocation(itemLink)

    -- inventory
    ---@return ItemInfo[]
    local getEquippedItems = function()
        return GetEquippedItemsForEquipLocation(character, equipmentLocation)
    end

    -- stored containers: bags and bank-like containers known to DataStore
    ---@return ItemInfo[]
    local getStoredContainerItems = function()
        ---@type ItemInfo[]
        local items = {}
        IterateStoredContainerItems(character, function(containerId, container, slotId, itemId, storedItemLink)
            local storedEquipmentLocation = GetItemEquipLocation(storedItemLink)
            if EquipLocationsMatch(storedEquipmentLocation, equipmentLocation) and storedItemLink ~= itemLink and IsComparableItemForCharacter(storedItemLink, itemLink, character) then
                table.insert(items, storedItemLink)
            end
        end)

        return items
    end

    -- mails
    ---@return ItemInfo[]
    local getMailItems = function()
        if not DataStore.IterateMails then
            --@alpha@
            HandMeDowns:Print("warn: DataStore.IterateMails not available.")
            --@end-alpha@
            return {}
        end

        ---@type ItemInfo[]
        local items = {}
        DataStore:IterateMails(character, function(icon, count, mailItemLink, money, text, returned)
            local mailEquipmentLocation = mailItemLink and GetItemEquipLocation(mailItemLink)
            if EquipLocationsMatch(mailEquipmentLocation, equipmentLocation) and mailItemLink ~= itemLink and IsComparableItemForCharacter(mailItemLink, itemLink, character) then
                table.insert(items, mailItemLink)
            end
        end)

        return items
    end

    ---@type ItemInfo?
    local bestItem
    local items = tableConcat(tableConcat(getEquippedItems(), getStoredContainerItems()), getMailItems())
    for _, item in ipairs(items) do
        if item and IsComparableItemForCharacter(item, itemLink, character) then
            if not bestItem or CompareItemsForCharacter(character, item, bestItem) == 1 then
                bestItem = item
            end
        end
    end

    --@debug@
    if bestItem then
        HandMeDowns:Print("Best item level for " .. character .. ": " .. (GetActualItemLevel(bestItem) or 0))
    end
    --@end-debug@
    return bestItem
end
