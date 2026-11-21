# ForeverUtils v2026.47.1

The first version: the options panel, minimap button and `/fu`, plus the first module.

## New

- **Target Finder.** Pick the mobs you're looking for and ForeverUtils keeps a `FUFind` macro, and a floating button, that target the nearest live one and mark it.
  - `/tf` opens the window. Type a name, or pick from mobs in your quest objectives and mobs you've recently seen.
  - If you have QuestieDB (it comes with Questie), the search covers every mob it knows.
  - The window lists your quests as sections you can open to see their mobs, including the mobs that drop items you need to collect. Shift-click a quest to find all its mobs at once.
  - `/tf <name>` finds a mob, `/tf + <name>` adds another, `/tf hover` finds the one under your cursor (there's a key binding for it too).
  - A **Find** button on the target frame, and entries in the target's right-click menu, set the mob you have targeted. Each can be turned off in the options.
  - Dead mobs are skipped unless you tick **Include dead mobs**.
  - Hovering a mob on your list says so on its tooltip, and whether it's the only one. This can be turned off in the options.

- **Options panel** under Options → AddOns → ForeverUtils, with a master on/off switch and a checkbox for each module.
- **Minimap button.** Left-click opens the options, right-click turns ForeverUtils on or off. It can be dragged around the minimap or hidden in the options.
- **`/fu`** opens the options. `/fu on|off`, `/fu status`, `/fu <module> [on|off]` and `/fu debug` are also available.
