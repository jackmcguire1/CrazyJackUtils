# CrazyJackUtils

*Formerly ForeverUtils.*

**Small, useful tools for WoW Forever in one addon. First up: Target Finder, which keeps a targeting macro up to date so you never edit one by hand again.**

CrazyJackUtils is a collection of utilities, each one a module you can turn on or off on its own. It starts with Target Finder and will grow over time.

## Target Finder

Looking for a particular mob? Pick it from a list and CrazyJackUtils writes the targeting macro for you. One press targets the nearest live one and puts a raid marker on it.

- **No more editing macros.** CrazyJackUtils creates a macro called `FUFind` and rewrites it whenever your find list changes. Put it on an action bar once and it always targets what you're currently looking for.
- **Search instead of typing exact names.** Type part of a name and pick from the matches. With Questie's database (QuestieDB) installed, the search covers every mob it knows.
- **Your quests, ready to pick from.** Open **Quests** in the window to see your unfinished quests with their mobs, including the mobs that drop items you need to collect. Click one to find it, or shift-click to add it to your list. Shift-click a quest to find all its mobs at once. Hover anything in the list to see what clicking it does.
- **Set it from the mob in front of you.** Target a mob and click **Find** on the target frame, pick **Find this mob** from its right-click menu, or hover a mob and press a key you've bound.
- **Several mobs at once.** Add more than one mob and the macro tries each in turn until it finds one. Use the arrows in the window to change the order, or click the magnifying glass beside a mob to go for that one.
- **History.** The window keeps the last ten mobs you looked for, so one you removed by accident is a click away.
- **Skips corpses.** Dead mobs are ignored unless you tick **Include dead mobs**.
- **No marker on tagged mobs.** If the mob it finds is tagged by another player, the marker comes back off it. The macro can't skip them, so you move on yourself.
- **A button if you'd rather click.** A small floating button targets with a click, opens the list with a right-click and finds a service with a shift-click. It can hide while you have nothing to find, or be turned off.
- **Tooltip reminder.** Hovering a mob on your find list says so, and whether it's the only one you're finding.
- **Find the nearest vendor, repairer or trainer.** Shift-click the floating button and pick a service. Target Finder puts the nearest one on your list and tells you how far away it is and which way. Needs QuestieDB.
- **Show a mob on the world map.** Click the map button beside a mob to open the map on the zone where it spawns, with its spawn points pinned. Hover a pin for details, shift-click it to remove it, or click the map button again to clear them all. Needs QuestieDB.
- **Spawn points on the minimap.** The places your mobs are known to spawn show on the minimap with your chosen raid marker. If none is in range, the nearest one sits on the rim to point the way. Needs QuestieDB.

## Getting started

1. Install CrazyJackUtils and log in.
2. Type `/tf` to open Target Finder.
3. Type a mob's name and press Enter, or open one of your quests and click a mob.
4. Click the floating button to target it. Or click **Pick up macro** and drop the `FUFind` macro on an action bar.

## Commands

| Command | What it does |
| --- | --- |
| `/tf` | Opens Target Finder |
| `/tf <name>` | Finds that mob, replacing your list |
| `/tf + <name>` | Adds a mob to your list |
| `/tf - <name>` | Removes a mob from your list |
| `/tf hover` | Finds the mob under your cursor, or your target |
| `/tf list` | Shows your find list |
| `/tf clear` | Empties your find list |
| `/tf nearest <service>` | Finds the nearest vendor, repair, banker, class trainer and so on |
| `/fu` | Opens the CrazyJackUtils options |
| `/fu on` or `/fu off` | Turns every module on or off |
| `/fu finder on` or `/fu finder off` | Turns Target Finder on or off |
| `/fu status` | Shows which modules are on |
| `/fu errors` | Shows any errors CrazyJackUtils caught and skipped |

## Options

Open them with `/fu`, the minimap button, or Options → AddOns → CrazyJackUtils.

- Turn CrazyJackUtils, or any single module, on or off.
- Choose the raid marker Target Finder puts on the mob it finds, or none. You can also pick it in the `/tf` window.
- Open the Target Finder window.
- Show or hide the floating button, the **Find** button on the target frame, the right-click menu entries, the tooltip line and the minimap spawn points.
- Show or hide the minimap button.

## Key bindings

Under Key Bindings → AddOns → CrazyJackUtils:

- **Find the mob under the cursor** sets your find list to the mob you're hovering.
- **Target a mob on the find list** does the same as clicking the floating button.

## Minimap button

- **Left-click** opens the options.
- **Right-click** turns CrazyJackUtils on or off.
- **Drag** moves it around the minimap.
- **MinimapButtonButton** and similar button collectors pick it up.
- It also appears in the minimap's AddOns dropdown.
- You can hide it in the options.

## Good to know

- **You still press a button to target.** WoW doesn't let addons target for you, so CrazyJackUtils maintains the macro and you press it.
- **About three mobs fit.** A macro holds 255 characters. Mobs that don't fit stay on your list, greyed out.
- **Changes wait for combat to end.** Macros can't be edited in combat, so a change made mid-fight applies when it's over.
- **Pressing the macro clears your target first.** If none of your mobs are nearby, you end up with no target.
- **The minimap shows spawn points, not the mob itself.** WoW doesn't tell addons where a mob is, so the markers show where it's known to spawn.
- **Profession and class trainers are matched by their title.** That works on English clients only.
- **QuestieDB is optional.** Without it, Target Finder suggests mobs from your quests' kill objectives (English clients only) and mobs you've been near. With it, you can search every mob, see which mobs drop quest items, find the nearest service and see spawn points on the minimap. QuestieDB's coverage of Forever's new mobs is still growing.
- **Don't rename the `FUFind` macro.** CrazyJackUtils finds it by name. Changing its icon is fine. The same goes for `FUFindOne`, a second macro the magnifying glasses use.
