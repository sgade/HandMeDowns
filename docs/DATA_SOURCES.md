# Data sources for spec preferences

HandMeDowns hardcodes two kinds of per-spec preference data in
`HandMeDowns.lua`: which weapon/shield subclasses a spec actually uses, and
which secondary stats a spec prefers. Both drift with patches. This doc
records where each came from and how to refresh it.

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

## Secondary stat priorities (`SpecSecondaryStatPriority`)

**Source**: Wowhead's per-spec "Stat Priority" guides, one page per
spec+role:

```
https://www.wowhead.com/guide/classes/<class-slug>/<spec-slug>/stat-priority-pve-<role>
```

where `<role>` is `dps`, `tank`, or `healer`. Last fetched 2026-08-19,
current for WoW patch 12.1 ("Midnight").

Unlike the weapon table, **this is theorycrafting, not Blizzard data** -
there is no DB2/API source for "which secondary stat a spec wants more."
Wowhead's guides are written from simulation results and top-player
consensus, and explicitly caveat that breakpoints, diminishing returns,
talents, and gear state all shift the real answer - a fresh sim of your own
character always beats a static list. Treat this table as a reasonable
default for tie-breaking, not ground truth.

**Method note**: fetching these URLs directly (plain HTTP GET, or a generic
web-fetch tool) tends to return only Wowhead's client-rendered navigation
chrome, not the actual guide text - the page content loads via JavaScript.
What worked during research was a **targeted web search** per spec, e.g.:

```
"Frost Mage" stat priority wowhead Crit Haste Mastery Versatility
```

The search engine's synthesized answer/snippet reliably surfaced the actual
priority line, e.g. for Frost Mage: `Crit ≈ Mastery > Haste > Versatility`,
plus the caveat text. If a query doesn't surface a clear priority line, try
adding "PvE", "single target", "raid", or the exact Wowhead URL to the
query before giving up on that spec.

**Transcription rule**: record the priority *exactly* as published,
preserving groupings:
- `>` between stats means strictly ranked - left is preferred over right.
- `≈` (or "~", "roughly equal", "within a few % of each other" in the
  guide text) means those stats are one **tier** - list them together in
  the same inner array in `SpecSecondaryStatPriority`, not as separate
  tiers. Do not collapse a `≈` group down to a single "pick one" stat.

Each spec's entry in `SpecSecondaryStatPriority` is an ordered array of
tiers (arrays of `SecondaryStat` keys). Comparison sums the tier's stat
amounts on each item and moves to the next tier only on an exact sum tie -
see `CompareItemStatsForCharacter` in `HandMeDowns.lua`.

There is deliberately no class-level fallback for stat priority (unlike the
weapon table's `ClassFavoriteWeaponSubclasses` union): stat order genuinely
differs by spec within the same class, so unioning would produce a
meaningless order. When a character's spec isn't known yet, or a spec has
no recorded priority, the tie-break is skipped entirely and the comparison
falls back to item level only.

**To refresh**: re-run the search-per-spec method above for all specs
(~39, one per spec+role) after a future patch or major balance pass, and
re-transcribe each spec's tiers.
