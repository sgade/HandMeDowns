# Data sources for spec preferences

HandMeDowns hardcodes one kind of per-spec preference data in
`Data.lua`: which weapon/shield subclasses a spec actually uses. It
drifts with patches - this doc records where it came from and how to
refresh it. Secondary stat preferences (Crit/Haste/Mastery/Versatility) are
**not** hardcoded; that comparison is delegated to the optional Pawn addon
when it's installed - see the second section below.

## Weapon and shield preferences (`SpecWeaponSubclasses`, `SpecUsesShield`)

**Source**: Blizzard's own `ChrSpecialization` game-data table, the
`Description_lang` field ("Preferred Weapon(s): ..."), queried from the
[wago.tools DB2 export](https://wago.tools/db2/ChrSpecialization). This is
mechanical, Blizzard-authored data, not theorycrafting - it only changes
when Blizzard changes which weapon types a spec can use.

Last fetched 2026-08-18, against live WoW patch 12.1 ("Midnight"),
including Devourer (spec id 1480), the third Demon Hunter spec added in
Midnight.

**To refresh**: re-fetch that same export (or an equivalent DBC/DB2 dump
from wowhead/wago after a future patch) and re-read each spec row's
`Description_lang` "Preferred Weapon" clause. The mapping from that text to
`WeaponSubclass`/`ArmorSubclass` constants is mechanical:
- "Two-Handed X" -> `X2H`
- a bare weapon name -> its 1H constant
- "Shield" -> `ArmorSubclass.Shield`
- inherently-2H types (Staff/Polearm/Bow/Gun/Crossbow/Warglaive) map
  directly, since `WeaponSubclass` only carries one entry for each

Cross-check every entry against the class-level `WeaponSubclassClasses` /
`ArmorSubclassClasses` tables in the same file, so nothing ends up
unreachable (the class-level check always runs first).

A few entries deliberately go beyond the official flavor text - these are
flagged inline in the source comments above `SetSpecWeaponSubclasses` calls
(e.g. Outlaw's off-hand dagger, Windwalker's Polearm/Staff pick). Re-verify
those still hold true each time this is refreshed; they can go stale
independently of the DB2 data.

## Item comparison (delegated to Pawn, `CompareItemValuesForScale`)

HandMeDowns used to hardcode a per-spec table of secondary stat priorities,
hand-transcribed from Wowhead's guides. That table is gone. Item comparison
is instead delegated live to the optional
[Pawn](https://github.com/VgerMods/Pawn) addon, if the player has it
installed - Pawn's entire purpose is scoring items against per-spec stat
weights (including main stat), so HandMeDowns just asks it rather than
maintaining its own, inherently-theorycrafted copy of the same data.

When Pawn is installed and a scale resolves for a character (see "Why a
scale is always available" below), its score is the *authoritative*
comparison between two items - not just a tie-break. That matters because
item level alone can't tell a same-slot Intellect item from a Strength one:
a higher-ilvl item with the wrong main stat can score worse than a
lower-ilvl item with the right one. Item level is only used as a fallback:
when Pawn isn't installed, the spec is unknown, or Pawn can't produce a
score for one of the two specific items being compared. See
`Assignment.CompareItemsForCharacter` in `Assignment.lua`, the single
comparator this all funnels through.

**Why this is possible**: Pawn exposes genuine global Lua functions other
addons can call - this isn't reverse-engineering. Pawn's own
ArkInventory-rule integration (`GetPawnStatusForArkInventoryRule` in
`Pawn.lua`) calls the exact same functions HandMeDowns uses, confirming
they're meant for cross-addon use. Verified by reading Pawn's actual source
(not a summarized/fetched version - see the "verification method" note
below) at `github.com/VgerMods/Pawn`, `master` branch, **Pawn version
2.13.16**, same `## Interface: 120100` as HandMeDowns, on 2026-08-19.

**Functions relied on** (all in `Pawn.lua`):
- `PawnGetItemData(itemLink)` - parses an item link into a table with
  `.Stats`, `.Level`, `.SocketBonusStats`. Link-based, so it works for any
  item link regardless of which character owns it, same as the WoW APIs
  HandMeDowns already calls directly (`C_Item.GetItemInfo` etc.).
- `PawnFindScaleForSpec(classID, specID)` - returns the name of a
  plugin-provided scale for a class+spec, or `nil`. **`classID` is
  Blizzard's numeric class ID (1-13)**; **`specID` here is the local 1-4
  spec index** (`GetSpecializationInfoForClassID`'s convention - confirmed
  against `ScaleTemplates.lua`'s own template entries, e.g. Druid Feral is
  listed as `ClassID 11, SpecID 2`), **not** the global spec ID DataStore
  and the rest of HandMeDowns use. `GetPawnLocalSpecIndex` in
  `Pawn.lua` converts between the two using `Data.lua`'s existing
  `SpecsByClass` ordering, which already matches this convention.
- `PawnGetSingleValueFromItem(item, scaleName)` - returns a single numeric
  score for that item against that scale (gems, sockets, and normalization
  handled internally by Pawn).

**Why a scale is always available**: `Pawn.toc` loads `AskMrRobot.lua`
unconditionally on retail (`[AllowLoadGameType mainline]`, not an optional
module or user-imported string). That file registers a `"MrRobot"`-provider
scale for every class+spec combination at login, so `PawnFindScaleForSpec`
resolves for any alt's class/spec the moment Pawn is installed, with no
per-user setup.

**This is not a documented or versioned API contract.** Every call in
`Pawn.lua` (`GetPawnScaleNameForCharacter`,
`GetPawnItemValue`) is defensive on purpose: it checks `type(...) ==
"function"` before calling anything, wraps every call in `pcall`, and
validates the type of whatever comes back before trusting it. Any failure
at any step - Pawn not installed, a renamed/removed function, an unexpected
return shape, an internal Pawn error - degrades silently to "no opinion",
identical to today's "spec unknown" fallback (item level becomes the
comparison, and an exact tie means neither item is recommended over the
other). Nothing here should ever be able to produce a visible error for a
player who simply doesn't have Pawn installed.

**Verification method note, for future reference**: a generic
fetch-and-summarize web tool *hallucinated* plausible-looking function
bodies for `Pawn.lua`/`Core.lua` that don't exist in the real files -this
was only caught by downloading the raw source directly (`curl` the
`raw.githubusercontent.com` URLs) and reading it. Don't trust a summarized
read of a large Lua file when re-verifying this integration; fetch and read
the actual source.

**To refresh**: if a future Pawn update renames or reshapes these functions
and HandMeDowns' Pawn integration silently stops contributing scores
(it will not error - see above), re-fetch Pawn's current source the same
way and re-check `PawnFindScaleForSpec`, `PawnGetItemData`, and
`PawnGetSingleValueFromItem` still exist with the same parameter order and
return shape.
