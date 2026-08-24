--[[----------------------------------------------------------------------------

  WarbandMeDowns/Settings.lua
  A read-only settings page: explains what the addon does and visualizes the
  warband priority order used internally to decide who gets an item next.
  Holds no state of its own - everything is read live from DataStore via
  WarbandMeDowns.Characters. See docs/UI_DESIGN.md for the UI conventions
  followed here, and WarbandMeDowns.lua for the license header covering the
  whole addon.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Settings = WarbandMeDowns.Settings or {}
-- Not aliased to a local `Settings` like other modules alias their table -
-- that name is Blizzard's global Settings API (Settings.RegisterCanvasLayoutCategory
-- etc.), used throughout this file, and a same-named local would shadow it.
local SettingsPage = WarbandMeDowns.Settings
local Characters = WarbandMeDowns.Characters

-- *** Layout constants (see docs/UI_DESIGN.md)

local PANEL_PADDING = 12
local ROW_HEIGHT = 22
local SECTION_HEADER_HEIGHT = 24

local ColumnWidths = { rank = 28, name = 130, realm = 90, level = 44, itemLevel = 50, bagsBank = 80, mail = 70 }

local ColorGold = { 1, 0.82, 0 }
local ColorMuted = { 0.6, 0.6, 0.6 }
local ColorBody = { 0.85, 0.85, 0.85 }

---@type Frame?
local Panel

-- *** Last-scanned times
--
-- DataStore's core module stamps a `lastUpdate` time() on every character
-- table it writes, exposed generically via DataStore:GetModuleLastUpdateByKey
-- (see Thaoky/DataStore, DataStore/API/Core.lua). Note DataStore_Containers
-- shares ONE combined timestamp for bags and bank - every bag- or bank-slot
-- scan stamps the same field - so "last bags check" and "last bank check"
-- cannot be told apart; DataStore_Mails does track its own separately.

local WarnedMissingLastUpdateAPI = false

---@param moduleName string
---@param character string
---@return number? epochSeconds
local function GetModuleLastUpdate(moduleName, character)
    if type(DataStore.GetModuleLastUpdateByKey) ~= "function" then
        --@alpha@
        if not WarnedMissingLastUpdateAPI then
            WarnedMissingLastUpdateAPI = true
            WarbandMeDowns:Print("warn: DataStore.GetModuleLastUpdateByKey not available.")
        end
        --@end-alpha@
        return nil
    end

    local success, lastUpdate = pcall(DataStore.GetModuleLastUpdateByKey, DataStore, moduleName, character)
    if not success or not lastUpdate or lastUpdate == 0 then
        return nil
    end
    return lastUpdate
end

---Formats an epoch-seconds timestamp as a short "time ago" string.
---@param epochSeconds number?
---@return string
local function FormatElapsed(epochSeconds)
    if not epochSeconds then
        return "—"
    end

    local elapsed = time() - epochSeconds
    if elapsed < 60 then
        return "just now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. "m ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. "h ago"
    else
        return math.floor(elapsed / 86400) .. "d ago"
    end
end

-- *** Row data

---Formats one warband character's row for the priority table, tolerant of
---DataStore fields that are nil because the character hasn't been scanned
---this session.
---@param character string
---@param rank number
---@return table
local function GetRowData(character, rank)
    local server, name = Characters.CharacterServerAndNameFromKey(character)

    local level = DataStore:GetCharacterLevel(character)
    local itemLevel = DataStore:GetAverageItemLevel(character)

    local classSuccess, _, classToken = pcall(DataStore.GetCharacterClass, DataStore, character)

    return {
        rank = rank,
        name = name or character,
        realm = (server and server ~= "") and server or "—",
        levelText = level and tostring(level) or "—",
        itemLevelText = (itemLevel and itemLevel > 0) and string.format("%.0f", itemLevel) or "—",
        isCurrent = character == DataStore.ThisCharKey,
        classToken = classSuccess and classToken or nil,
        bagsBankText = FormatElapsed(GetModuleLastUpdate("DataStore_Containers", character)),
        mailText = FormatElapsed(GetModuleLastUpdate("DataStore_Mails", character)),
    }
end

-- *** Panel construction

---Creates one column's fontstring, chained off the previous column so
---headers and rows always line up.
---@param parent Frame
---@param relativeTo Frame?
---@param width number
---@return FontString
local function CreateColumn(parent, relativeTo, width)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if relativeTo then
        text:SetPoint("LEFT", relativeTo, "RIGHT", 4, 0)
    else
        text:SetPoint("LEFT", parent, "LEFT", 0, 0)
    end
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

---Lazily builds a row's column fontstrings on first use, then always
---overwrites their values - rows are pooled and reused by the ScrollView, so
---nothing here may assume a clean frame.
---@param row Frame
---@param data table
local function InitializeRow(row, data)
    if not row.rankText then
        row.rankText = CreateColumn(row, nil, ColumnWidths.rank)
        row.nameText = CreateColumn(row, row.rankText, ColumnWidths.name)
        row.realmText = CreateColumn(row, row.nameText, ColumnWidths.realm)
        row.levelText = CreateColumn(row, row.realmText, ColumnWidths.level)
        row.itemLevelText = CreateColumn(row, row.levelText, ColumnWidths.itemLevel)
        row.bagsBankText = CreateColumn(row, row.itemLevelText, ColumnWidths.bagsBank)
        row.mailText = CreateColumn(row, row.bagsBankText, ColumnWidths.mail)
    end

    row.rankText:SetText(tostring(data.rank))
    row.rankText:SetTextColor(unpack(ColorMuted))

    row.nameText:SetText(data.name .. (data.isCurrent and " (You)" or ""))
    local classColor = data.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classToken]
    if classColor then
        row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        row.nameText:SetTextColor(1, 1, 1)
    end

    row.realmText:SetText(data.realm)
    row.realmText:SetTextColor(unpack(ColorMuted))

    row.levelText:SetText(data.levelText)
    row.itemLevelText:SetText(data.itemLevelText)

    row.bagsBankText:SetText(data.bagsBankText)
    row.bagsBankText:SetTextColor(unpack(ColorMuted))

    row.mailText:SetText(data.mailText)
    row.mailText:SetTextColor(unpack(ColorMuted))
end

---Builds a header row mirroring InitializeRow's column layout exactly.
---@param parent Frame
---@return Frame
local function CreateHeaderRow(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(SECTION_HEADER_HEIGHT)

    local rank = CreateColumn(header, nil, ColumnWidths.rank)
    local name = CreateColumn(header, rank, ColumnWidths.name)
    local realm = CreateColumn(header, name, ColumnWidths.realm)
    local level = CreateColumn(header, realm, ColumnWidths.level)
    local itemLevel = CreateColumn(header, level, ColumnWidths.itemLevel)
    local bagsBank = CreateColumn(header, itemLevel, ColumnWidths.bagsBank)
    local mail = CreateColumn(header, bagsBank, ColumnWidths.mail)

    rank:SetText("#")
    name:SetText("Character")
    realm:SetText("Realm")
    level:SetText("Level")
    itemLevel:SetText("iLvl")
    bagsBank:SetText("Bags/Bank")
    mail:SetText("Mail")

    for _, column in ipairs({ rank, name, realm, level, itemLevel, bagsBank, mail }) do
        column:SetFontObject("GameFontNormalSmall")
        column:SetTextColor(unpack(ColorMuted))
    end

    return header
end

---Builds the static chrome once: title, explanation, column headers, and the
---scrollable priority table. Idempotent - safe to call multiple times.
---@return Frame
local function BuildPanel()
    if Panel then
        return Panel
    end

    Panel = CreateFrame("Frame")

    local title = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", Panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING)
    title:SetText("WarbandMeDowns")
    title:SetTextColor(unpack(ColorGold))

    local explanation = Panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    explanation:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    explanation:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)
    explanation:SetJustifyH("LEFT")
    explanation:SetWordWrap(true)
    explanation:SetTextColor(unpack(ColorBody))
    explanation:SetText(
        "WarbandMeDowns ranks your warband to decide who should get each piece of warbound gear. " ..
        "Characters are ordered by current level first, then by average equipped item level - both read " ..
        "live from DataStore. This is the exact order used everywhere the addon makes a recommendation. " ..
        "Pawn, if installed, decides which of two items is better for a given character's spec, but it " ..
        "never changes this ranking. Use /wmd why <item link> to see how a particular item was assigned."
    )

    local divider = Panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", explanation, "BOTTOMLEFT", 0, -12)
    divider:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    local sectionLabel = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
    sectionLabel:SetText("Warband Priority Order")
    sectionLabel:SetTextColor(unpack(ColorGold))

    local headerRow = CreateHeaderRow(Panel)
    headerRow:SetPoint("TOPLEFT", sectionLabel, "BOTTOMLEFT", 0, -8)
    headerRow:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)

    local scrollBox = CreateFrame("Frame", nil, Panel, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", Panel, "BOTTOMRIGHT", -(PANEL_PADDING + 20), PANEL_PADDING)

    local scrollBar = CreateFrame("EventFrame", nil, Panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT")
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT")

    local scrollView = CreateScrollBoxListLinearView()
    scrollView:SetElementExtent(ROW_HEIGHT)
    scrollView:SetElementInitializer("Frame", InitializeRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)

    Panel.scrollView = scrollView
    Panel:SetScript("OnShow", SettingsPage.RefreshTable)

    return Panel
end

-- *** Refresh

---Rebuilds the priority table from Characters.GetSortedWarbandCharacters().
---Called whenever the settings page is shown, since DataStore state (levels,
---item levels, which characters have been scanned) can change between
---visits. Recomputing on every show is cheap - a small warband and a
---handful of DataStore reads per character - so no caching is needed here.
function SettingsPage.RefreshTable()
    if not Panel or not Panel.scrollView then
        return
    end

    local dataProvider = CreateDataProvider()
    for rank, character in ipairs(Characters.GetSortedWarbandCharacters()) do
        dataProvider:Insert(GetRowData(character, rank))
    end

    Panel.scrollView:SetDataProvider(dataProvider)
end

-- *** Registration

---Builds and registers the WarbandMeDowns settings category. Safe to call
---once from OnInitialize. Never throws: a Settings API failure is printed as
---a warning instead of breaking the rest of the addon's startup.
function SettingsPage:Initialize()
    local success, errorMessage = pcall(function()
        local panel = BuildPanel()
        local category = Settings.RegisterCanvasLayoutCategory(panel, "WarbandMeDowns")
        Settings.RegisterAddOnCategory(category)
    end)

    if not success then
        WarbandMeDowns:Print("warn: could not register settings page: " .. tostring(errorMessage))
    end
end
