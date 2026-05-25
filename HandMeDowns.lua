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

---@param link ItemInfo
---@return number
local function GetActualItemLevel(link)
    local level, _, _ = C_Item.GetDetailedItemLevelInfo(link)
    return level
end

---@param character string
---@param itemLink ItemInfo
---@return boolean
local function CanCharacterEquipItem(character, itemLink)
    local itemClassID, itemSubclassID = GetItemClassAndSubclass(itemLink)
    if itemClassID ~= LE_ITEM_CLASS_ARMOR then
        return false
    end

    local classesThatWearTheItemSubType = {}
    if itemSubclassID == LE_ITEM_ARMOR_CLOTH then
        classesThatWearTheItemSubType = {"PRIEST", "MAGE", "WARLOCK"}
    elseif itemSubclassID == LE_ITEM_ARMOR_LEATHER then
        classesThatWearTheItemSubType = {"ROGUE", "MONK", "DRUID", "DEMONHUNTER"}
    elseif itemSubclassID == LE_ITEM_ARMOR_MAIL then
        classesThatWearTheItemSubType = {"HUNTER", "SHAMAN", "EVOKER"}
    elseif itemSubclassID == LE_ITEM_ARMOR_PLATE then
        classesThatWearTheItemSubType = {"WARRIOR", "PALADIN", "DEATHKNIGHT"}
    elseif itemSubclassID == LE_ITEM_ARMOR_GENERIC then
        -- trinkets, rings, etc
        classesThatWearTheItemSubType = {"WARRIOR", "PALADIN", "DEATHKNIGHT", "HUNTER", "SHAMAN", "EVOKER", "ROGUE", "MONK", "DRUID", "DEMONHUNTER", "PRIEST", "MAGE", "WARLOCK"}
    --@alpha@
    else
        HandMeDowns:Print("warn: unknown armor subclass '" .. tostring(itemSubclassID) .. "'")
    --@end-alpha@
    end

    local _, class = DataStore:GetCharacterClass(character)

    return arrayContains(classesThatWearTheItemSubType, class)
end

local function GetItemEquipLocation(link)
    local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfo(link)
    return itemEquipLoc
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

-- Reimplementation from DataStore_Containers
local function IterateBagItems(character, callback)
    for containerId, container in pairs(DataStore:GetContainers(character)) do
        for slotId = 1, DataStore:GetContainerSize(character, containerId) do
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
    -- stub
end

function HandMeDowns:OnEnable()
    HandMeDowns:HookItemTooltips()

    --@debug@
    HandMeDowns:Print("Ready.")
    --@end-debug@
end

function HandMeDowns:HookItemTooltips()
    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(frame, ...)
            if frame == GameTooltip and HandMeDowns:IsEnabled() then
                return HandMeDowns:OnTooltipSetItem(frame, ...)
            end
        end)
    else
        -- legacy
        GameTooltip:HookScript('OnTooltipSetItem', function (...)
            HandMeDowns:OnTooltipSetItem(...)
        end)
    end
end

function HandMeDowns:OnDisable()
    --@debug@
    HandMeDowns:Print("Disabled.")
    --@end-debug@
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

    local upgradeInfo = HandMeDowns:FindBestCharacterForItem(itemLink)
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

    frame:AddLine(distributionInfo .. " Upgrade from " .. upgradeInfo[2] .. " to " .. upgradeInfo[3] .. ".", 0, 0.75, 0.33, false)
end

-- *** Finding the best character for an item

---Finds the best character to wear a given item
---@param link ItemInfo
---@return [string, number, number]? upgradeInfo
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
    return HandMeDowns:FindUpgradeForCharactersOnAccount(DataStore.ThisAccount, link)
end

---@param accountName string
---@param itemLink ItemInfo
---@return [string, number, number]? upgradeInfo
function HandMeDowns:FindUpgradeForCharactersOnAccount(accountName, itemLink)
    local upgrades = {}
    for realmName in pairs(DataStore:GetRealms(accountName)) do
        for _, character in pairs(DataStore:GetCharacters(realmName, accountName)) do
            local upgradeInfo = HandMeDowns:FindUpgradeForCharacter(itemLink, character)

            if upgradeInfo then
                table.insert(upgrades, upgradeInfo)
            end
        end
    end

    table.sort(upgrades, function(left, right)
        local leftLevel = DataStore:GetCharacterLevel(left[1]) or 0
        local rightLevel = DataStore:GetCharacterLevel(right[1]) or 0
        if leftLevel ~= rightLevel then
            return leftLevel > rightLevel
        end

        local leftItemLevel = DataStore:GetAverageItemLevel(left[1]) or 0
        local rightItemLevel = DataStore:GetAverageItemLevel(right[1]) or 0
        return leftItemLevel > rightItemLevel
    end)

    return upgrades[1]
end

---@param itemLink ItemInfo
---@param character string
---@return boolean
local function IsComparableItemForCharacter(itemLink, character)
    if not itemLink then
        return false
    end

    return CanCharacterEquipItem(character, itemLink)
end

---Retrieves upgrade information about the given item for the character.
---If the item is an upgrade, upgrade info is returned, `nil` otherwise.
---
---@param itemLink ItemInfo
---@param character string
---@return [string, number, number]? upgradeInfo
function HandMeDowns:FindUpgradeForCharacter(itemLink, character)
    if not CanCharacterEquipItem(character, itemLink) then
        return
    end

    local itemLevel = GetActualItemLevel(itemLink)
    if not itemLevel then
        -- comparison not possible
        return
    end

    local compareItemLevel = HandMeDowns:GetBestCompareItemLevel(itemLink, character)
    if not compareItemLevel then
        compareItemLevel = 0
    end

    if compareItemLevel >= itemLevel then
        -- available item is equal or better than the one we compare for
        return
    end

    return {
        character,
        compareItemLevel,
        itemLevel
    }
end

---Finds the best available item level as comparison for the given item.
---
---@param itemLink ItemInfo The item to compare against.
---@param character string The character to search within.
---@return number?
function HandMeDowns:GetBestCompareItemLevel(itemLink, character)
    local equipmentLocation = GetItemEquipLocation(itemLink)

    -- inventory
    ---@return ItemInfo[]
    local getEquippedItems = function()
        return GetEquippedItemsForEquipLocation(character, equipmentLocation)
    end

    -- bags
    ---@return ItemInfo[]
    local getBagItems = function()
        ---@type ItemInfo[]
        local items = {}
        IterateBagItems(character, function(containerId, container, slotId, itemId, bagItemLink)
            local bagEquipmentLocation = GetItemEquipLocation(bagItemLink)
            if bagEquipmentLocation == equipmentLocation and bagItemLink ~= itemLink and IsComparableItemForCharacter(bagItemLink, character) then
                table.insert(items, bagItemLink)
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
            if mailEquipmentLocation == equipmentLocation and mailItemLink ~= itemLink and IsComparableItemForCharacter(mailItemLink, character) then
                table.insert(items, mailItemLink)
            end
        end)

        return items
    end

    ---@type number?
    local bestItemLevel
    local items = tableConcat(tableConcat(getEquippedItems(), getBagItems()), getMailItems())
    for _, item in ipairs(items) do
        if item and IsComparableItemForCharacter(item, character) then
            local itemLevel = GetActualItemLevel(item)

            if itemLevel and (not bestItemLevel or bestItemLevel < itemLevel) then
                bestItemLevel = itemLevel
            end
        end
    end

    --@debug@
    if bestItemLevel then
        HandMeDowns:Print("Best item level for " .. character .. ": " .. bestItemLevel)
    end
    --@end-debug@
    return bestItemLevel
end
