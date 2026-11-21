# ForeverUtils

**Small, useful tools for WoW Forever in one addon. First up: Target Finder, which keeps a targeting macro up to date so you never edit one by hand again.**

ForeverUtils is a collection of utilities, each one a module you can turn on or off on its own. It starts with Target Finder and will grow over time.

## Target Finder

Looking for a particular mob? Pick it from a list and ForeverUtils writes the targeting macro for you. One press targets the nearest live one and puts a raid marker on it.

- **No more editing macros.** ForeverUtils creates a macro called `FUFind` and rewrites it whenever your find list changes. Put it on an action bar once and it always targets what you're currently looking for.
- **Search instead of typing exact names.** Type part of a name and pick from the matches. With Questie's database (QuestieDB) installed, the search covers every mob it knows.
- **Your quests, ready to pick from.** The window lists your unfinished quests. Open one to see its mobs, including the mobs that drop items you need to collect, and click one to find it. Shift-click a quest to find all its mobs at once.
- **Set it from the mob in front of you.** Target a mob and click **Find** on the target frame, pick **Find this mob** from its right-click menu, or hover a mob and press a key you've bound.
- **Several mobs at once.** Add more than one mob and the macro tries each in turn until it finds one.
- **Skips corpses.** Dead mobs are ignored unless you tick **Include dead mobs**.
- **A button if you'd rather click.** A small floating button appears while you're finding something. Click it to target, right-click it to change the list.
- **Tooltip reminder.** Hovering a mob on your find list says so, and whether it's the only one you're finding.

## Getting started

1. Install ForeverUtils and log in.
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
| `/fu` | Opens the ForeverUtils options |
| `/fu on` or `/fu off` | Turns every module on or off |
| `/fu finder on` or `/fu finder off` | Turns Target Finder on or off |
| `/fu status` | Shows which modules are on |

## Options

Open them with `/fu`, the minimap button, or Options → AddOns → ForeverUtils.

- Turn ForeverUtils, or any single module, on or off.
- Choose the raid marker Target Finder puts on the mob it finds, or none.
- Show or hide the floating button, the **Find** button on the target frame, the right-click menu entries and the tooltip line.
- Show or hide the minimap button.

## Key bindings

Under Key Bindings → AddOns → ForeverUtils:

- **Find the mob under the cursor** sets your find list to the mob you're hovering.
- **Target a mob on the find list** does the same as clicking the floating button.

## Minimap button

- **Left-click** opens the options.
- **Right-click** turns ForeverUtils on or off.
- **Drag** moves it around the minimap.
- **MinimapButtonButton** and similar button collectors pick it up.
- It also appears in the minimap's AddOns dropdown.
- You can hide it in the options.

## Good to know

- **You still press a button to target.** WoW doesn't let addons target for you, so ForeverUtils maintains the macro and you press it.
- **Three or four mobs fit.** A macro holds 255 characters. Mobs that don't fit stay on your list, greyed out.
- **Changes wait for combat to end.** Macros can't be edited in combat, so a change made mid-fight applies when it's over.
- **Pressing the macro clears your target first.** If none of your mobs are nearby, you end up with no target.
- **QuestieDB is optional.** Without it, Target Finder suggests mobs from your quests' kill objectives (English clients only) and mobs you've been near. With it, you can search every mob and see which mobs drop quest items. QuestieDB's coverage of Forever's new mobs is still growing.
- **Don't rename the `FUFind` macro.** ForeverUtils finds it by name. Changing its icon is fine.
