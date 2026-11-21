# ForeverUtils

A WoW: Forever addon that collects small utilities in one place. Each utility is a **module** that can be turned on or off on its own.

## In game

- Click the minimap button to open the options, or right-click it to turn ForeverUtils on or off. Drag it to move it around the minimap.
  - The button is named `ForeverUtils_MinimapButton`, so MinimapButtonButton collects it.
  - It also appears in the minimap's AddOns dropdown.
  - You can hide it in the options.
- Open the options with `/fu` (or `/foreverutils`), or go to Options → AddOns → ForeverUtils.
- `/fu on|off` turns everything on or off. `/fu <module>` toggles one module, and `/fu <module> on|off` sets it.
- `/fu status` lists the modules. `/fu debug` prints what the addon is doing.

## Target Finder

Replaces a hand-edited targeting macro. You pick the mobs; ForeverUtils keeps a general macro called `FUFind` up to date, and that macro does the targeting. Addons can't target units themselves, so there is always a macro or button to press.

With Black Ooze and Green Ooze on the list, the macro is:

```
/cleartarget
/targetexact Black Ooze
/cleartarget [dead]
/targetexact [noexists] Green Ooze
/cleartarget [dead]
/tm [exists,nodead] 1
```

- **Picking mobs**
  - `/tf` opens the window. Type a name and press Enter, or click a suggestion. Shift-click, or Shift+Enter, adds to the list instead of replacing it.
  - With nothing typed, the window lists a section per unfinished quest, open to start with, then "Recently seen mobs", "Nearest services" and "Nearest profession trainers", closed to start with. Click a section to open or close it (it stays that way), click a mob in it to find that mob, or shift-click a quest to find all its mobs. The list scrolls with the mouse wheel.
  - Quest mobs come from QuestieDB when it's installed: the mobs to kill, and for "collect" objectives the mobs that drop the item. Without it they're read from unfinished kill objectives' text (English clients only).
  - Recently seen mobs are ones you've hovered, targeted or seen a nameplate for.
  - With the [QuestieDB](https://github.com/Questie/QuestieDB) addon installed (Questie uses it), typing also searches every NPC it knows. ForeverUtils reads the names through QuestieDB's public API (`NpcDB.GetAllIds` and `NpcDB.name`) the first time the window opens; nothing is bundled. Without it, only quest mobs and mobs you've seen are suggested.
  - `/tf <name>` finds one mob, `/tf + <name>` adds one, `/tf - <name>` removes one, `/tf clear` empties the list and `/tf list` prints it.
  - With a mob targeted, click the **Find** button on the target frame (shift-click adds instead of replacing), or right-click the target's portrait and pick **Find this mob** or **Add to find list**. Both can be turned off in the options panel.
  - `/tf hover` finds the mob under your cursor, or your target. It's also a key binding: Key Bindings → AddOns → ForeverUtils → "Find the mob under the cursor".
- **Nearest services** (needs QuestieDB)
  - Shift-click the floating button for a menu: Vendor, Repair, Banker, Innkeeper, Flight master, Auctioneer, Stable master, Class trainer, and a submenu of profession trainers. Picking one replaces the find list with the nearest NPC offering it and prints how far away it is and in which direction.
  - The window lists the same under **Nearest services** and **Nearest profession trainers**, with distances. `/tf nearest <service>` does it from chat.
  - Only NPCs on your continent and friendly to your faction count. "Nearest" is in a straight line.
  - Services come from QuestieDB's NPC flags. Class and profession trainers are told apart by their title ("Warrior Trainer", "Herbalism Trainer"), which works on English clients only.
- **Minimap spawn points** (needs QuestieDB)
  - Addons can't see where a mob is, so the minimap shows where the mobs on your list are known to spawn (`NpcDB.spawns`), drawn with the chosen raid marker, or a gold dot if you chose none.
  - If no spawn point is within the minimap's range, the nearest one is drawn on the rim, slightly faded, to point the way.
  - Turn it off with **Show spawn points on the minimap** in the options panel.
- **Targeting**
  - The floating button stays on screen; with nothing to find it reads "Target Finder" and a click opens the window. Untick **Keep the button when there's nothing to find** in the options to have it show only while the list isn't empty. Click it to target, right-click to open the window, Shift-click for the nearest-services menu, Shift-drag to move it.
  - In the window, the magnifying glass beside a mob on your list targets just that mob. It runs a second macro, `FUFindOne`, which is written for that mob as you click and created the first time you use a magnifying glass. `FUFind` is never touched by it. These are secure buttons laid over the window rather than part of it, so the window can still be opened and moved in combat; they're hidden while you're in combat.
  - **Pick up macro** in the window puts `FUFind` on your cursor to drop on an action bar.
  - "Target a mob on the find list" in the key bindings presses the floating button.
- **Settings**
  - **Include dead mobs** in the window drops the `[dead]` checks.
  - **Mark with** in the window picks the raid marker, or none. It's also in the options panel, along with whether the floating button shows and an **Open Target Finder** button.
  - **Show on mob tooltips** in the options panel adds a line when you hover a mob on your list: "the only mob you're finding", or "finding, 2 of 3 on your list". It only adds a line, so other addons' tooltip lines are unaffected.
- **Limits**
  - A macro holds 255 characters, which is three or four mobs. Ones that don't fit are greyed out in the window.
  - Macros and the floating button can't change in combat. Changes made in combat apply when it ends.
  - Pressing the macro clears your target first, so if nothing is found you end up with no target.

The logic is in `Modules/Finder.lua` and tested by `spec/finder_spec.lua`. The window and button are in `Modules/FinderUI.lua` and need checking in game.

## Layout

```
ForeverUtils/            the addon, as it's installed
  ForeverUtils.toc
  Core.lua               saved variables, module registry, slash command
  Modules/               one file per utility
  Bindings.xml           key bindings
  Options.lua            options panel and the ns.UI widgets
  Minimap.lua            minimap button
spec/                    busted tests and the fake WoW client
tools/build.py           TOC check, zip and install
```

## Adding a module

1. Create `ForeverUtils/Modules/<Name>.lua`:

   ```lua
   local _, ns = ...

   local module = ns.RegisterModule({
     key = "autosell",              -- saved-variable key, and the word after /fu
     name = "Auto Sell",
     description = "Sells grey items when you visit a vendor.",
     defaults = { keepCloth = false },
     events = {
       MERCHANT_SHOW = function(self)
         if not self.db.keepCloth then ns.Debug("selling") end
       end,
     },
   })

   function module:OnEnable() end   -- optional; also OnInit and OnDisable

   -- Optional: extra controls under the module's checkbox in the options.
   function module:BuildOptions(UI, anchor)
     return UI.Checkbox("Keep cloth", nil, self.db, "keepCloth", anchor)
   end
   ```

2. Add `Modules\<Name>.lua` to `ForeverUtils.toc`, between `Core.lua` and `Options.lua`. `mise run build` fails if you forget.
3. Add any new WoW globals it uses to `read_globals` in `.luacheckrc`.
4. Test it in `spec/<name>_spec.lua` with `wow.load({ files = { "ForeverUtils/Modules/<Name>.lua" }, env = { ... } })`, passing stand-ins for the WoW API it calls in `env`.

How modules behave:

- A module's settings live in `ForeverUtilsDB.modules[key]` and are available as `module.db` from `OnInit` onwards. `defaults` fills in missing settings. `enabled` is added automatically and defaults to `true`; put `enabled = false` in `defaults` for an opt-in module.
- A module is active when both ForeverUtils and the module are enabled. `OnEnable` and `OnDisable` are called when that changes, and `events` handlers are only called while it's active.
- `ns.UI` has `Label`, `Checkbox`, `Button` and `Dropdown` for `BuildOptions`. Each is placed under the `anchor` it's given.

## Developing

Tools are managed by [mise](https://mise.jdx.dev): `mise.toml` pins uv, Lua 5.1, lua-language-server and actionlint. uv manages Python.

```sh
mise install && mise run setup   # once: tools, luacheck, busted and the WoW API annotations
mise run lint
mise run test
mise run zip                     # dist/ForeverUtils.zip
WOW_ADDONS="/path/to/World of Warcraft/_forever_/Interface/AddOns" mise run install
```

### Linting

- **luacheck** checks the code against Lua 5.1, the Lua version WoW uses. It catches typos in global names, unused variables and accidental globals. Allowed WoW globals are listed in `.luacheckrc`.
- **lua-language-server** checks calls against [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api), pinned by `WOW_API_REV` in `mise.toml`. These annotations describe the modern WoW client, which Forever's API is based on. Globals from Blizzard's UI code, such as `Settings`, aren't in the annotations, so they're declared in `.luarc.json`.
- **actionlint** checks the GitHub Actions workflows.

### Testing

The tests use [busted](https://lunarmodules.github.io/busted/) and live in `spec/`.

- **`spec/helpers/wow.lua`** is a fake WoW client. It loads `Core.lua`, and any module files asked for, into a fresh environment for each test. Tests send in events with `w:Fire(...)` and slash commands with `w:Slash(...)`.
- **`spec/core_spec.lua`** covers saved variables, the module registry and the slash commands.

The options panel and minimap button aren't tested, since they're almost all WoW UI calls. Check them in game.

### Build

`tools/build.py` checks that every file in the TOC exists and every `.lua` file in the addon is in the TOC, then zips or installs the addon.

## CI and releases

- **Shared checks (`checks.yml`):** the lint job runs `mise run lint` and `mise run test`. The build job runs `mise run zip` and uploads the zip as a downloadable file.
- **`development.yml`:** runs the checks on every pull request.
- **`production.yml`:** runs the checks on every push to `main`, then creates a **draft prerelease** with `ForeverUtils-v<version>.zip` attached.
  - The version comes from `## Version` in `ForeverUtils/ForeverUtils.toc`.
  - A new push to `main` replaces that version's draft.
  - Once you publish a release, later pushes with the same version leave it alone.
  - Versions are calendar-based: `<year>.<ISO week>.<release that week>`, for example `2026.47.1`. `date +%G.%V` prints the first two parts.
  - To release a new version, bump `## Version` in the `.toc` and rewrite `CHANGELOG.md`, which becomes the release notes.

### CurseForge

When you publish a GitHub release, `curseforge.yml` uploads that release's `ForeverUtils-v<version>.zip` to CurseForge. It's the same file `production.yml` built and checked.

- **Game version:** taken from `## Interface` in the `.toc`. For example `16001` becomes WoW Forever `1.60.1`.
- **Changelog:** taken from `CHANGELOG.md`.
- **File type:** a GitHub prerelease is uploaded to CurseForge as a beta file; anything else as a release.
- **Re-uploading:** to upload an existing release again, run the workflow manually from the Actions tab and give it the tag.

It needs the `CF_PROJECT_ID` repository variable and the `CF_API_TOKEN` repository secret, both already set. Without them the workflow skips the upload. `DESCRIPTION.md` is the text for the CurseForge project page and is pasted in by hand.

## License

[Apache License 2.0](LICENSE).
