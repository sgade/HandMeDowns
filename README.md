# HandMeDowns

[![GitHub Release](https://img.shields.io/github/v/release/sgade/HandMeDowns?sort=semver&display_name=release&style=for-the-badge&logo=github&color=rgb(20%2C4%2C120))](https://github.com/sgade/HandMeDowns/releases)

Recommends alt characters for bind-on-equip and warbound gear.

HandMeDowns uses DataStore to compare the hovered item against every character
on the account, current character included. Characters are ranked in priority
order by current level first, then equipped average item level, and checked in
that order; the first eligible character is the recommendation. A character is
eligible when it can use the hovered item and does not already have an
equal-or-better item for that equip location equipped, in bags, in the bank, or
in the mailbox. If the current character comes first in that priority order,
the tooltip recommends keeping the item; otherwise it recommends sending it to
whichever character does.

When two comparable items share the exact same item level, the tie is broken by
secondary stats: each character's spec has a recorded stat priority (e.g. Crit
&gt; Haste &gt; Mastery &gt; Versatility), and whichever item carries more of the
higher-priority stat wins. If the character's spec isn't known yet (no
DataStore_Talents scan), or the spec has no recorded priority, item level is the
only comparison and a tie means neither item is recommended over the other. See
[docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) for where the weapon and stat
preference data comes from and how to refresh it.

Armor, shields, and weapons are checked against class-compatible item
subclasses. One-handed weapons are compared against both main-hand and off-hand
slots when the item can go in either hand. Weapon comparisons only consider the
same weapon subclass, so a character's better sword does not block a dagger
recommendation.

Required item level is intentionally not checked, so gear can be sent to an alt
for later leveling.

Recommendation results are cached by item link and cleared when local bag, bank,
mail, equipment, level, or item-info data changes. Cache invalidation is repeated
briefly after those events so DataStore has time to finish scanning the changed
data.

## Dependencies

- DataStore
- DataStore_Characters
- DataStore_Inventory
- DataStore_Containers
- DataStore_Mails

## Optional dependencies

- DataStore_Talents
