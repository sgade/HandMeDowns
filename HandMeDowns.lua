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
            if frame == GameTooltip and self:IsEnabled() then
                return self:OnTooltipSetItem(frame, ...)
            end
        end)
    else
        -- legacy
        GameTooltip:HookScript('OnTooltipSetItem', function (...)
            self:OnTooltipSetItem(...)
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

    local target = HandMeDowns:FindBestCharacterForItem(itemLink)
    if not target then
        return
    end

    frame:AddLine("HandMeDowns! Send this to " .. target[1] .. " (Upgrade from " .. target[3] .. " to " .. target[4] .. ")", 0, 0.75, 0.33, false)
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
---@return (string|number)?
function HandMeDowns:GetBestCompareItem(itemLink, character)
    local equipLocation = GetItemEquipLocation(itemLink)

    -- inventory
    ---@return (string|number)[]
    local getInventoryItems = function()
        if not DataStore.GetInventoryItem then
            HandMeDowns:Print("warn: DataStore.GetInventoryItem not available.")
            return {}
        end

        local inventoryType = C_Item.GetItemInventoryTypeByID(itemLink)
        if not inventoryType then
            return {}
        end

        return {DataStore.GetInventoryItem(character, inventoryType - 1)}
    end

    -- bags
    ---@return (string|number)[]
    local getBagItems = function()
        if not DataStore.IterateBags then
            HandMeDowns:Print("warn: DataStore.GetContainers not available.")
            return {}
        end

        ---@type (string|number)[]
        local items = {}
        DataStore:IterateBags(character, function(containerId, container, slotId, itemId)
            if GetItemEquipLocation(itemId) then
                table.insert(items, itemId)
            end
        end)

        return items
    end

    -- mails
    ---@return (string|number)[]
    local getMailItems = function()
        if not DataStore.IterateMails then
            HandMeDowns:Print("warn: DataStore.IterateMails not available.")
            return {}
        end

        ---@type (string|number)[]
        local items = {}
        DataStore:IterateMails(character, function(icon, count, itemLink, money, text, returned)
            if GetItemEquipLocation(itemLink) == equipLocation then
                table.insert(items, itemLink)
            end
        end)

        return items
    end

    ---@type (string|number)?
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
