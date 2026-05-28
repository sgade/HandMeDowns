# HandMeDowns

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

Required item level is intentionally not checked, so gear can be sent to an alt
for later leveling.

## Requirements

- DataStore
- DataStore_Characters
- DataStore_Inventory
- DataStore_Containers
- DataStore_Mails
