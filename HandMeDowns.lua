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
    HandMeDowns:Print("Initialized.")
end

function HandMeDowns:OnEnable()
    HandMeDowns:HookItemTooltips()
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

    HandMeDowns:Print("Tooltips hooked.")
end

function HandMeDowns:OnDisable()
    HandMeDowns:Print("Disabled.")
end

-- *** Setting the tooltip

---Hooks the tooltip
---@param frame GameTooltip
function HandMeDowns:OnTooltipSetItem(frame, ...)
    ---@type string, string
    local _, itemLink = frame:GetItem()

    local target = HandMeDowns:FindBestCharacterForItem(itemLink)
    if not target then
        return
    end

    frame:AddLine("HandMeDowns! Send this to " .. target[1] .. " (Upgrade from " .. target[3] .. " to " .. target[4] .. ")", 0, 0.75, 0.33, false)
end

-- *** Finding the best character for an item

---Finds the best character to wear a given item
---@param link string|number
---@return [string, string?, number, number]? upgradeInfo
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

    if HandMeDowns:IsUpgradeForCharacter(link, "player") then
        local playerName, server = UnitName("player")
        local level = GetActualItemLevel(link)

        return {
            playerName,
            server,
            0,
            level
        }
    end
end

---@return boolean
function HandMeDowns:IsUpgradeForCharacter(itemLink, character)
    if not (character == "player") then
        -- other characters are not currently supported
        HandMeDowns:Print("Other characters are currently not supported.")
        return false
    end

    local inventoryType = C_Item.GetItemInventoryTypeByID(itemLink)
    if not inventoryType then
        return false
    end

    local level, _ = GetActualItemLevel(itemLink)

    local equippedItemLink = GetInventoryItemLink(character, inventoryType)
    local equippedLevel
    if not equippedItemLink then
        equippedLevel = 0
    else
        equippedLevel = GetActualItemLevel(equippedItemLink)
    end

    return equippedLevel < level
end
