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

## Layout

```
ForeverUtils/            the addon, as it's installed
  ForeverUtils.toc
  Core.lua               saved variables, module registry, slash command
  Modules/               one file per utility
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
  - To release a new version, bump `## Version` in the `.toc` and rewrite `CHANGELOG.md`, which becomes the release notes.

There is no CurseForge upload yet.

## License

[Apache License 2.0](LICENSE).
