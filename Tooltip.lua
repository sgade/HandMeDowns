--[[----------------------------------------------------------------------------

  HandMeDowns/Tooltip.lua
  Addon lifecycle, the GameTooltip hook, and cache-invalidation event wiring.
  See HandMeDowns.lua for the license header covering the whole addon.

----------------------------------------------------------------------------]]--

local Characters = HandMeDowns.Characters

local CacheInvalidationFrame

-- *** Lifecycle

function HandMeDowns:OnInitialize()
    CacheInvalidationFrame = CreateFrame("Frame")
    CacheInvalidationFrame:SetScript("OnEvent", function()
        HandMeDowns.Assignment:MarkDirty()
    end)
end

function HandMeDowns:OnEnable()
    HandMeDowns:HookItemTooltips()
    HandMeDowns:RegisterCacheInvalidationEvents()

    --@debug@
    HandMeDowns:Print("Ready.")
    --@end-debug@
end

function HandMeDowns:OnDisable()
    if CacheInvalidationFrame then
        CacheInvalidationFrame:UnregisterAllEvents()
    end

    HandMeDowns.Assignment:Reset()

    --@debug@
    HandMeDowns:Print("Disabled.")
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

    local result = HandMeDowns.Assignment:GetBestCharacterForItem(itemLink)
    if not result then
        return
    end

    if result == HandMeDowns.Assignment.Sell then
        frame:AddLine("HandMeDowns! No character can use this - sell it.", 0, 0.75, 0.33, false)
        return
    end

    local upgradeInfo = result

    local distributionInfo = (function()
        if upgradeInfo[1] == DataStore.ThisCharKey then
            return "Use here!"
        else
            local characterServer, characterName = Characters.CharacterServerAndNameFromKey(upgradeInfo[1])
            return "HandMeDowns! Send this to " .. characterName .. "@" .. characterServer .. "."
        end
    end)()

    local upgradeDescription
    if upgradeInfo[4] then
        if upgradeInfo[3] == upgradeInfo[2] then
            -- Same item level as what's already available, but better
            -- secondary stats for the character's spec.
            upgradeDescription = "Better secondary stats at item level " .. upgradeInfo[3] .. "."
        else
            -- Pawn is authoritative and prefers this item despite a lower
            -- item level than what's already available.
            upgradeDescription = "Better secondary stats despite lower item level (" ..
                upgradeInfo[2] .. " -> " .. upgradeInfo[3] .. ")."
        end
    else
        upgradeDescription = "Upgrade from " .. upgradeInfo[2] .. " to " .. upgradeInfo[3] .. "."
    end

    frame:AddLine(distributionInfo .. " " .. upgradeDescription, 0, 0.75, 0.33, false)
end
