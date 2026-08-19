# HandMeDowns

[![GitHub Release](https://img.shields.io/github/v/release/sgade/HandMeDowns?sort=semver&display_name=release&style=for-the-badge&logo=github&color=rgb(20%2C4%2C120))](https://github.com/sgade/HandMeDowns/releases)

Recommends alt characters for bind-on-equip and warbound gear.

HandMeDowns uses DataStore to precompute, for the whole account, which
character should end up with which warbound item - not just the one under
your mouse. Every character's equipped gear, bags, bank, and mailbox are
scanned together, so a spare sitting unlooked-at in one alt's bag can cascade
down to a lower-priority alt instead of being invisible to the recommendation.
Characters are ranked in priority order by current level first, then equipped
average item level, and walked in that order for each equipment slot; each
eligible character gets the better of their own current gear and the best
still-unclaimed candidate for that slot. If the current character ends up
with the hovered item, the tooltip recommends keeping it; if a different
character does, it recommends sending it there; if nobody in the warband ends
up wanting it, it recommends selling it. Currently equipped gear is never
itself reassigned to another character - only bag/bank/mail spares are
eligible to move.

This precomputed result is cached and only redone when something that could
change it actually happens (see caching, below); worst case, it's brought up
to date the moment you hover a warbound item, so the tooltip is always
correct even if nothing warmed the cache first.

The warband priority order (level, then average item level) is decided by a
single, swappable comparator function, so a different ordering (e.g. a manual
per-character order) can be dropped in later without touching anything that
consumes it.

When two comparable items share the exact same item level, the tie is broken by
secondary stats - but only if the optional [Pawn](https://github.com/VgerMods/Pawn)
addon is installed. HandMeDowns doesn't keep its own stat preference data; it
asks Pawn to score both items against the character's spec and recommends
whichever one Pawn values higher. Without Pawn installed, or if the character's
spec isn't known yet (no DataStore_Talents scan), item level is the only
comparison and a tie means neither item is recommended over the other. See
[docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) for where the weapon preference
data comes from, how the Pawn integration works, and how to refresh both.

Armor, shields, and weapons are checked against class-compatible item
subclasses. One-handed weapons are compared against both main-hand and off-hand
slots when the item can go in either hand. Weapon comparisons only consider the
same weapon subclass, so a character's better sword does not block a dagger
recommendation.

Required item level is intentionally not checked, so gear can be sent to an alt
for later leveling.

The full warband assignment is cached and marked stale (not eagerly
recomputed) when local bag, bank, mail, equipment, level, or item-info data
changes - recomputing right after looting, possibly mid-combat, is a worse
time than the moment you actually look at a tooltip. A background recompute
is attempted shortly after those events settle, but only while out of combat;
either way, the next tooltip hover always brings the result up to date
itself, so correctness never depends on the background attempt running.
Invalidation is repeated briefly after those events so DataStore has time to
finish scanning the changed data.

## Dependencies

- DataStore
- DataStore_Characters
- DataStore_Inventory
- DataStore_Containers
- DataStore_Mails

## Optional dependencies

- DataStore_Talents
- Pawn
