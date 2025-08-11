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
---@return number level Item level
---@return Enum.InventoryType location
---@return Enum.ItemBind bindType
local function ShortItemInfo(link)
    local _, _, _, _, _, _, _, _, location, _, _, _, _, bindType = C_Item.GetItemInfo(link)
    local level, _, _ = C_Item.GetDetailedItemLevelInfo(link)
    return level, location, bindType
end

---@param bindType Enum.ItemBind
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
    HandMeDowns:Print(self, "Initialized.")
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

    HandMeDowns:Print(self, "Tooltips hooked.")
end

function HandMeDowns:OnDisable()
    HandMeDowns:Print(self, "Disabled.")
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
    local level, location, bind = ShortItemInfo(link)
    if not level or not location or not bind or bind == Enum.ItemBind.None then
        -- item cannot be equipped
        return
    end

    if not CanItemBeSentToTwink(bind) then
        -- item cannot be traded to twinks
        return
    end

    local inventoryType = C_Item.GetItemInventoryTypeByID(link)
    if not inventoryType then
        return
    end

    local equippedItemLink = GetInventoryItemLink("player", inventoryType)
    local equippedLevel
    if not equippedItemLink then
        equippedLevel = 0
    else
        equippedLevel, _, _ = ShortItemInfo(equippedItemLink)
    end

    if equippedLevel >= level then
        return
    end

    local playerName, server = UnitName("player")
    return {
        playerName,
        server,
        equippedLevel,
        level
    }
    -- return playerName
end
