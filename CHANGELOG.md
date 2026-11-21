# ForeverUtils v2026.47.2

Target Finder can now find the nearest vendor, repairer or trainer for you, and shows where your mobs spawn on the minimap.

## New

- **Find the nearest service.** Shift-click the floating button and pick Vendor, Repair, Banker, Innkeeper, Flight master, Auctioneer, Stable master, Class trainer or a profession trainer. Target Finder puts the nearest one on your find list and tells you how far away it is and in which direction.
  - The `/tf` window lists the same services under **Nearest services** and **Nearest profession trainers**, with the distance to each.
  - `/tf nearest repair` does it from chat. `/tf nearest` lists the services.
  - This needs QuestieDB, and only covers NPCs on your continent that are friendly to your faction.
- **Spawn points on the minimap.** The places your mobs are known to spawn show on the minimap, drawn with the raid marker you chose. If none is in range, the nearest one sits on the minimap's rim to point the way. This needs QuestieDB and can be turned off in the options.
  - These are spawn points, not live positions. WoW doesn't tell addons where a mob actually is.

## Changed

- **The floating button stays put.** It no longer disappears when your find list is empty, so the shift-click menu is always there. Clicking it with nothing to find opens the window. Untick **Keep the button when there's nothing to find** in the options to have it hide again.
- **Options.** Target Finder's settings now sit together in their own section.

## Fixed

- **Overlapping text in the `/tf` window.** The grey hint no longer runs into the heading above the list.
