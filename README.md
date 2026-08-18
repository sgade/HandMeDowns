# HandMeDowns

[![GitHub Release](https://img.shields.io/github/v/release/sgade/HandMeDowns?sort=semver&display_name=release&style=for-the-badge&logo=github&color=rgb(20%2C4%2C120))](https://github.com/sgade/HandMeDowns/releases)

Recommends alt characters for bind-on-equip and warbound gear.

HandMeDowns uses DataStore to compare the hovered item against characters on the
account. The current character is checked first. If the item is an upgrade and
the character does not already have an equal-or-better item equipped, in bags,
in the bank, or in the mailbox, the tooltip recommends keeping the item.

If the current character does not need the item, other characters are considered
in priority order by current level first, then equipped average item level. A
character is eligible when it can use the hovered item and does not already have
an equal-or-better item for that equip location equipped, in bags, in the bank,
or in the mailbox.

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
