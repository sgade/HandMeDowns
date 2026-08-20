# UI Design: Building a Modern WoW Addon Settings UI

This is the authoritative reference for any settings/options UI in WarbandMeDowns.
Short and precise on purpose - a cheat sheet, not a tutorial. Verify against the
sources below before deviating from it.

## Sources

- [`Blizzard_ImplementationReadme.lua`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) -
  Blizzard's own shipped implementation notes for the Settings API (via the
  Gethe/wow-ui-source mirror of the extracted client Lua/XML - there is no
  separate official Blizzard addon-API doc site, so this mirror is the addon
  community's primary source).
- [Warcraft Wiki: Settings API](https://warcraft.wiki.gg/wiki/Settings_API)
- [Warcraft Wiki: Creating a settings menu](https://warcraft.wiki.gg/wiki/Creating_a_settings_menu)
- [Warcraft Wiki: Making scrollable frames](https://warcraft.wiki.gg/wiki/Making_scrollable_frames)
- [Warcraft Wiki: Patch 10.2.0/API changes](https://warcraft.wiki.gg/wiki/Patch_10.2.0/API_changes) -
  Blizzard's own migration note deprecating `Backdrop` and the old NineSlice
  utility.

A reference addon, ClassCodex, was also studied. Its fonts/colors/spacing
conventions are sound and reused below, but its chrome (hand-rolled
`BackdropTemplate` + tooltip-border textures) and its list (a manual
row-pool) predate the current standard and are **not** followed here - see
the "chrome" and "lists" sections.

## 1. Settings API: which category type

| Need | Use | API |
|---|---|---|
| A stack of checkboxes/dropdowns/sliders bound to SavedVariables | Vertical layout | `Settings.RegisterVerticalLayoutCategory(name)` |
| A custom layout (header, explanation text, a table, anything hand-drawn) | Canvas layout | `Settings.RegisterCanvasLayoutCategory(frame, name)` |

Rule of thumb: **form controls → vertical; custom content → canvas.**

Both return a `category` object; register it the same way in either case:

```lua
local category = Settings.RegisterCanvasLayoutCategory(frame, "MyAddon")
Settings.RegisterAddOnCategory(category)
```

Open it programmatically with `Settings.OpenToCategory(category:GetID())`.

## 2. Canvas frame rule: don't build your own window

The Settings window already provides the outer chrome. A canvas panel is
just content dropped into an already-framed page - Blizzard's own minimal
example is nothing more than a plain frame and a flat texture:

```lua
local frame = CreateFrame("Frame")
local background = frame:CreateTexture()
background:SetAllPoints(frame)
background:SetColorTexture(1, 0, 1, 0.5)

local category = Settings.RegisterCanvasLayoutCategory(frame, "My AddOn")
Settings.RegisterAddOnCategory(category)
```

- **Never call `frame:SetSize(...)`** on the canvas frame - the Settings
  window owns its size. "If no anchor points are provided, the frame will be
  anchored to TOPLEFT(0,0) and BOTTOMRIGHT(0,0) in the panel space."
- Anchor your content *inside* the frame with padding (`PANEL_PADDING`, see
  §8), not by resizing the frame itself.
- The frame is created once but shown many times. Refresh anything
  data-driven from `panel:SetScript("OnShow", RefreshFn)`, never assume the
  data is still fresh from last time.

## 3. Lists/tables: `ScrollBox` + `DataProvider`, not a manual row-pool

The current, documented list system - the standard replacement for the older
`FauxScrollFrameTemplate`/manual-pool style:

```lua
local ScrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
local ScrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
ScrollBox:SetPoint(...); ScrollBar:SetPoint(...)

local ScrollView = CreateScrollBoxListLinearView()
ScrollView:SetElementExtent(ROW_HEIGHT)          -- required when the element
                                                  -- has no XML template to
                                                  -- infer a height from
ScrollView:SetElementInitializer("Frame", function(row, data)
    -- lazily build child fontstrings/textures on first use, then set
    -- their values from `data`. Rows are POOLED AND REUSED, so always
    -- overwrite every field you set here - never assume a clean frame.
end)

ScrollUtil.InitScrollBoxListWithScrollBar(ScrollBox, ScrollBar, ScrollView)

local DataProvider = CreateDataProvider()
ScrollView:SetDataProvider(DataProvider)
DataProvider:Insert(rowData)   -- one call per row
```

Key facts:
- `SetElementInitializer` accepts either an XML template name **or a bare
  frame type** (`"Frame"`). Passing a bare type avoids needing any
  addon-authored XML - keeps a pure-Lua codebase pure - but then you must
  supply the row height yourself via `SetElementExtent`.
- To refresh the table, create a fresh `DataProvider` and call
  `ScrollView:SetDataProvider(newProvider)` again - simpler and safer than
  relying on an in-place clear method, and don't hide/show a fixed pool by
  hand.

## 4. Chrome: don't add a border unless you need one

As of Patch 10.2.0, Blizzard's own API notes state a new texture-slicing
system was added "as a replacement for both the deprecated Backdrop system
and the script-based NineSlice panel layout utility," recommended for new
code going forward.

- **Default: no border at all.** The canonical canvas example (§2) has none
  - the Settings window already frames the page.
  - Never use `Interface\Tooltips\UI-Tooltip-Background`/`SetBackdrop` for
  new chrome; it is legacy.
- If a region genuinely needs a visual inset (e.g. to separate a table from
  the text above it), use the modern primitive instead:
  ```lua
  local tex = frame:CreateTexture()
  tex:SetAllPoints(frame)
  tex:SetTextureSliceMargins(left, right, top, bottom)
  tex:SetTextureSliceMode(Enum.UITextureSliceMode.Tiled) -- or .Stretched
  ```
- A thin 1px `SetColorTexture(0.3, 0.3, 0.3, 0.6)` divider line remains fine
  for separating sections - it's a flat texture, not a deprecated backdrop.

## 5. Typography

| Font object | Use |
|---|---|
| `GameFontNormal` | Titles/headers (tint gold per §6 for emphasis) |
| `GameFontNormalSmall` | Secondary/body labels |
| `GameFontHighlight` | Emphasized text (names, values) |
| `GameFontHighlightSmall` | Small emphasized text, table cells |
| `GameFontDisableSmall` | Muted subtitle/help text |

## 6. Colors

Hardcoded RGB, not Blizzard's named color globals (`NORMAL_FONT_COLOR` etc.)
- this is a stylistic convention, not an API requirement, but keep it
consistent within the addon:

| Token | RGB | Use |
|---|---|---|
| Brand gold | `(1, 0.82, 0)` | Titles, section headers |
| Muted grey | `(0.5-0.7, 0.5-0.7, 0.5-0.7)` | Secondary/de-emphasized text |
| Body grey | `(0.85, 0.85, 0.85)` | Explanation/help paragraph text |
| Actionable green | `(0.45, 0.75, 0.45)` | Hints, "this is you" markers |
| Warning orange | `(1, 0.65, 0.15)` | Warnings |

## 7. Spacing tokens

| Token | Value |
|---|---|
| `PANEL_PADDING` | 12 |
| `CONTENT_INSET` | 8 |
| `ROW_HEIGHT` | 22 |
| `SECTION_HEADER_HEIGHT` | 24 |
| Divider height | 1 |
| Section gap | 3-4 |

## 8. Header + explanation pattern

1. Gold `GameFontNormal` title, top-anchored with `PANEL_PADDING`.
2. A wrapped `GameFontHighlightSmall` (or body-grey, §6) paragraph below it -
   `SetWordWrap(true)`, width bound to the panel width minus padding. 2-4
   sentences: what the addon does, in plain language.
3. A thin 1px `SetColorTexture(0.3, 0.3, 0.3, 0.6)` divider separating the
   explanation from whatever comes next.

## 9. Recipe: building a new settings page end-to-end

1. New module file, following the repo's convention: license-referencing
   header comment, `WarbandMeDowns.<Module> = WarbandMeDowns.<Module> or {}`,
   LuaDoc on every function.
2. Build the canvas frame (§2) - no size, no border.
3. Add the header/explanation block (§8).
4. If tabular: add the `ScrollBox`/`DataProvider` list (§3).
5. Register with `Settings.RegisterCanvasLayoutCategory` +
   `Settings.RegisterAddOnCategory`, both wrapped in `pcall` so a Settings-API
   failure prints a warning instead of breaking the addon's `OnInitialize`.
6. Hook a refresh function to `panel:SetScript("OnShow", ...)` for any
   data-driven content.
7. Verify in-game: `Escape > Options > AddOns > <name>`.
