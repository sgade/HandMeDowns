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

---@param link number|string
---@return Enum.ItemBind bindType
local function GetItemBind(link)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(link)
    return bindType
end

---@param link number|string
---@return number
local function GetActualItemLevel(link)
    local level, _, _ = C_Item.GetDetailedItemLevelInfo(link)
    return level
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
        if character == DataStore.ThisCharKey then
            return GetInventoryItemID("player", slotId)
        end
        return DataStore.GetInventoryItem(character, slotId)
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
        Enum.ItemBind.None,
        Enum.ItemBind.OnEquip,
        Enum.ItemBind.OnUse,
        Enum.ItemBind.ToWoWAccount,
        Enum.ItemBind.ToBnetAccount,
        Enum.ItemBind.ToBnetAccountUntilEquipped
    }
    return arrayContains(relevantForTwinks, bindType)
end

-- Reimplementation from DataStore_Containers
local function IterateBagItems(character, callback)
    if not character.Containers then return end

    for containerId, container in pairs(character.Containers) do
        for slotId = 1, DataStore:GetContainerSize(character, containerId) do
            local itemId = DataStore:GetSlotInfo(container, slotId)

            -- Callback only if there is an item in that slot
            if itemId then
                callback(containerId, container, slotId, itemId)
            end
        end
    end
end

---@param key string
---@return string?, string?
local function CharacterServerAndNameFromKey(key)
    ---@type string?
    local server = nil
    ---@type string?
    local name = nil
    for part in string.gmatch(key, "%a+") do
        server = name
        name = part
    end
    return server, name
end

-- *** Lifecyle

function HandMeDowns:OnInitialize()
    -- stub
end

function HandMeDowns:OnEnable()
    HandMeDowns:HookItemTooltips()

    HandMeDowns:Print("Ready.")
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
    HandMeDowns:Print("Disabled.")
end

-- *** Setting the tooltip

---Hooks the tooltip
---@param frame GameTooltip
function HandMeDowns:OnTooltipSetItem(frame, ...)
    ---@type string, string|number
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
---@param link string|number
---@return [string, number, number]? upgradeInfo
function HandMeDowns:FindBestCharacterForItem(link)
    local bind = GetItemBind(link)
    if not bind or bind == Enum.ItemBind.None then
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
    return HandMeDowns:FindUpgradeForCharacterOnAccount(DataStore.ThisAccount, link)
end

---@return [string, number, number]? upgradeInfo
function HandMeDowns:FindUpgradeForCharacterOnAccount(account, itemLink)
    -- TODO: instead of going through all realms and characters, go through a priorized list
    for realm in pairs(DataStore:GetRealms(account)) do
        local upgradeInfo = HandMeDowns:FindUpgradeForCharacterOnRealm(realm, account, itemLink)
        if upgradeInfo then
            return upgradeInfo
        end
    end

    return nil
end

---@return [string, number, number]? upgradeInfo
function HandMeDowns:FindUpgradeForCharacterOnRealm(realm, account, itemLink)
    for characterName, character in pairs(DataStore:GetCharacters(realm, account)) do
        local upgradeInfo = HandMeDowns:FindUpgradeForCharacter(itemLink, character)

        if upgradeInfo then
            return upgradeInfo
        end
    end

    return nil
end

---Retrieves upgrade information about the given item for the character.
---If the item is an upgrade, upgrade info is returned, `nil` otherwise.
---
---@param itemLink string|number
---@param character string
---@return [string, number, number]? upgradeInfo
function HandMeDowns:FindUpgradeForCharacter(itemLink, character)
    local bestCompareItem = HandMeDowns:GetBestCompareItem(itemLink, character)
    if not bestCompareItem then
        -- no item to compare against
        return
    end

    local availableItemLevel = GetActualItemLevel(bestCompareItem)
    local itemLevel = GetActualItemLevel(itemLink)

    if availableItemLevel > itemLevel then
        -- available item is better than the one we compare for
        return
    end

    return {
        character,
        availableItemLevel,
        itemLevel
    }
end

---Finds the best item as comparison for the given item.
---
---@param itemLink string|number The item to compare against.
---@param character string The character to search within.
---@return ItemInfo?
function HandMeDowns:GetBestCompareItem(itemLink, character)
    local equipmentLocation = GetItemEquipLocation(itemLink)

    -- inventory
    ---@return ItemInfo[]
    local getInventoryItems = function()
        if not DataStore.GetInventoryItem then
            HandMeDowns:Print("warn: DataStore.GetInventoryItem not available.")
            return {}
        end

        return GetEquippedItemsForEquipLocation(character, equipmentLocation)
    end

    -- bags
    ---@return ItemInfo[]
    local getBagItems = function()
        -- if not DataStore.IterateBags then
        --     HandMeDowns:Print("warn: DataStore.IterateBags not available.")
        --     return {}
        -- end

        ---@type ItemInfo[]
        local items = {}
        IterateBagItems(character, function(containerId, container, slotId, itemId)
            if GetItemEquipLocation(itemId) then
                table.insert(items, itemId)
            end
        end)

        return items
    end

    -- mails
    ---@return ItemInfo[]
    local getMailItems = function()
        if not DataStore.IterateMails then
            HandMeDowns:Print("warn: DataStore.IterateMails not available.")
            return {}
        end

        ---@type ItemInfo[]
        local items = {}
        DataStore:IterateMails(character, function(icon, count, itemLink, money, text, returned)
            if GetItemEquipLocation(itemLink) == equipmentLocation then
                table.insert(items, itemLink)
            end
        end)

        return items
    end

    ---@type ItemInfo?
    local bestItem
    local items = tableConcat(tableConcat(getInventoryItems(), getBagItems()), getMailItems())
    for _, item in ipairs(items) do
        if not bestItem then
            bestItem = item
        elseif item then
            local bestItemLevel = GetActualItemLevel(bestItem)
            local itemLevel = GetActualItemLevel(item)

            if bestItemLevel > itemLevel then
                bestItem = item
            end
        end
    end

    return bestItem
end
