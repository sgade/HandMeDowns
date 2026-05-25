# HandMeDowns

Recommends alt characters for bind-on-equip and warbound gear.

HandMeDowns uses DataStore to compare the hovered item against other characters
on the account. Characters are considered in priority order by current level
first, then equipped average item level. A character is eligible when it can use
the hovered item and does not already have an equal-or-better item for that equip
location equipped, in its bags, or in its mailbox.

Required item level is intentionally not checked, so gear can be sent to an alt
for later leveling.

## Requirements

- DataStore
- DataStore_Characters
- DataStore_Inventory
- DataStore_Containers
- DataStore_Mails
