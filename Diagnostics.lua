--[[----------------------------------------------------------------------------

  WarbandMeDowns/Diagnostics.lua
  The /wmd slash command, for inspecting why the engine reached a given
  recommendation. See WarbandMeDowns.lua for the license header covering the
  whole addon.

  The recommendation is a global assignment over the whole warband, so "why
  did it pick that character?" is not answerable from the tooltip line alone -
  it depends on every other character's floor and on which comparison basis
  each of them ended up using. `/wmd why <item link>` prints that table.

  The most useful column is `basis`: "pawn" means Pawn's per-spec score
  decided it, "ilvl" means the addon fell back to raw item level for that
  character (Pawn not installed, spec unknown, or Pawn could not score one of
  the items involved). A warband where every row says "ilvl" while Pawn is
  installed means the spec lookup is broken again - that exact failure is what
  made every recommendation item-level-only for a long time.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Diagnostics = WarbandMeDowns.Diagnostics or {}
local Diagnostics = WarbandMeDowns.Diagnostics
local Assignment = WarbandMeDowns.Assignment
local Characters = WarbandMeDowns.Characters

local ColorHeading = "|cffffd100"
local ColorMuted = "|cff909090"
local ColorGood = "|cff40d060"
local ColorWarn = "|cffff8040"
local ColorReset = "|r"

---Pulls a usable item link out of whatever the player typed. A shift-clicked
---link arrives complete (colour codes and all) and works as-is with every
---C_Item function; a bare item ID or plain name is passed through for
---C_Item.GetItemInfo to resolve.
---@param input string
---@return string?
local function ParseItemArgument(input)
    if not input then
        return nil
    end

    local trimmed = input:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    return trimmed
end

---Pads to `width` first and colours afterwards: colour escapes count toward
---string.format's field width but take up no space on screen, so colouring
---before padding silently breaks the column alignment.
---@param text string
---@param width number
---@param color string?
---@return string
local function Pad(text, width, color)
    local padded = string.format("%-" .. width .. "s", text)
    if not color then
        return padded
    end
    return color .. padded .. ColorReset
end

---@param score number?
---@return string
local function FormatScore(score)
    if not score then
        return ColorMuted .. "-" .. ColorReset
    end
    return string.format("%.1f", score)
end

---@param link ItemInfo?
---@return string
local function FormatItem(link)
    if not link then
        return ColorMuted .. "(none)" .. ColorReset
    end
    return link
end

---@param row table
---@return string
local function FormatVerdict(row)
    if not row.eligible then
        return ColorMuted .. "cannot use this item type" .. ColorReset
    end
    if row.unresolved then
        return ColorWarn .. "WAITING on item data" .. ColorReset
    end
    if row.isWinner then
        return ColorGood .. "CLAIMS IT" .. ColorReset
    end
    if row.beatsFloor == nil then
        return ColorWarn .. "undecidable" .. ColorReset
    end
    if row.beatsFloor == 1 then
        -- An upgrade for them, but they are not who it goes to: either a
        -- higher-priority character claimed this copy first, or the pool had
        -- something even better for them.
        return "an upgrade, but claimed elsewhere"
    end
    return "keeps what they have"
end

---@param explanation table
local function PrintExplanation(explanation)
    WarbandMeDowns:Print(ColorHeading .. "why" .. ColorReset .. " " .. tostring(explanation.link))

    if explanation.rejection then
        WarbandMeDowns:Print("  not recommendable: " .. explanation.rejection)
        return
    end

    WarbandMeDowns:Printf(
        "  ilvl %s, quality %s, %s, slot-class %s",
        tostring(explanation.itemLevel),
        tostring(explanation.quality),
        tostring(explanation.equipLoc),
        tostring(explanation.slotClassKey)
    )

    for _, row in ipairs(explanation.rows) do
        if not row.eligible then
            WarbandMeDowns:Printf(
                "  %s%2d%s %-18s %s",
                ColorMuted, row.rank, ColorReset,
                row.displayName .. (row.isCurrent and " (you)" or ""),
                FormatVerdict(row)
            )
        else
            local usesPawn = row.basis == "pawn"
            WarbandMeDowns:Printf(
                "  %s%2d%s %-18s %s %s floor %s (%s) vs item %s -- %s",
                ColorMuted, row.rank, ColorReset,
                row.displayName .. (row.isCurrent and " (you)" or ""),
                Pad(usesPawn and "pawn" or "ilvl", 4, not usesPawn and ColorWarn or nil),
                Pad(row.scaleName or "no scale", 22, not row.scaleName and ColorMuted or nil),
                FormatItem(row.floor),
                FormatScore(row.floorScore),
                FormatScore(row.itemScore),
                FormatVerdict(row)
            )
        end
    end
end

---@param itemLink string
local function ExplainAndPrint(itemLink)
    local success, explanation = pcall(Assignment.ExplainItem, Assignment, itemLink)
    if not success then
        WarbandMeDowns:Print("error: " .. tostring(explanation))
        return
    end

    PrintExplanation(explanation)
end

local function PrintUsage()
    WarbandMeDowns:Print("usage:")
    WarbandMeDowns:Print("  /wmd why <item link>  - explain who the engine gives this item to, and why")
    WarbandMeDowns:Print("  /wmd ranks            - print the warband priority order")
    WarbandMeDowns:Print("  /wmd refresh          - force a full recompute now")
    WarbandMeDowns:Print("(shift-click an item into chat to paste its link)")
end

local function PrintRanks()
    Assignment:EnsureFresh()

    WarbandMeDowns:Print(ColorHeading .. "warband priority order" .. ColorReset)
    for rank, character in ipairs(Characters.GetSortedWarbandCharacters()) do
        local level = DataStore:GetCharacterLevel(character) or 0
        local itemLevel = DataStore:GetAverageItemLevel(character) or 0
        local specIndex = Characters.GetKnownSpecIndex(character)
        local scaleName = WarbandMeDowns.Pawn.GetPawnScaleNameForCharacter(character)

        WarbandMeDowns:Printf(
            "  %s%2d%s %-18s level %-3d ilvl %-6.1f spec %-4s %s",
            ColorMuted, rank, ColorReset,
            Characters.GetDisplayName(character) .. (character == DataStore.ThisCharKey and " (you)" or ""),
            level,
            itemLevel,
            specIndex and tostring(specIndex) or "?",
            scaleName or (ColorWarn .. "no Pawn scale" .. ColorReset)
        )
    end
end

---AceConsole handler for /wmd.
---@param input string
function WarbandMeDowns:HandleChatCommand(input)
    local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()

    if command == "why" then
        local itemLink = ParseItemArgument(rest)
        if not itemLink then
            WarbandMeDowns:Print("usage: /wmd why <item link>")
            return
        end
        ExplainAndPrint(itemLink)
    elseif command == "ranks" then
        PrintRanks()
    elseif command == "refresh" then
        Assignment:MarkDirty()
        Assignment:EnsureFresh()
        WarbandMeDowns:Print("recomputed.")
    else
        PrintUsage()
    end
end

function Diagnostics:Initialize()
    WarbandMeDowns:RegisterChatCommand("wmd", "HandleChatCommand")
end
