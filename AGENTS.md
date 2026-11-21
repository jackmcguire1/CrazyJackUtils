# Working on ForeverUtils

ForeverUtils is a World of Warcraft addon for the WoW: Forever client (Interface 16001). It is a hub of small utilities, each one a module. `README.md` describes the features, layout, module API, tooling and release process in full; read it first. This file covers what an agent needs on top of that.

## Commands

```sh
mise install && mise run setup   # once
mise run lint                    # luacheck, lua-language-server, actionlint
mise run test                    # busted
mise run build                   # checks the .toc lists every .lua file
```

Run lint and test before calling a change done. Both must pass in CI.

## Nothing here runs in a real client

There is no WoW client on the development machine. The tests run against a fake client in `spec/helpers/wow.lua`.

- Put logic in the module file (`Modules/Finder.lua`) where the tests can reach it, and test it in `spec/`.
- Keep frames, textures and menus in the UI file (`Modules/FinderUI.lua`). That file is not loaded by the tests.
- Say plainly in your summary which parts are untested in game. Do not claim a UI change works.

## WoW rules that shape the code

- **Addons can't target units.** Targeting always goes through a macro or a secure button the player presses.
- **Nothing protected changes in combat.** Macros can't be created or edited, and secure buttons can't be shown, hidden, moved or given attributes. Check `InCombatLockdown()`, defer to `PLAYER_REGEN_ENABLED`.
- **Don't parent or anchor secure buttons to the `/tf` window.** A frame with protected children can't be shown, hidden or moved in combat. The magnifying glasses are children of `UIParent` laid over the window's rows for this reason.
- **Never create a macro at login.** The macro list may not have loaded, and a second copy would be made. Only edit one that exists; create on a player action.
- **A macro holds 255 characters.**
- **Addons can't see where a mob is.** The minimap pins are QuestieDB's spawn points, not live positions.
- **Values from the game can be secret.** Check with `issecretvalue` before comparing or doing arithmetic on unit names, positions and the like.
- **QuestieDB is optional.** Guard every use of `NpcDB`, `QuestDB`, `ItemDB` and `LibQuestieDB`, and keep a fallback or a clear message for players without it.

## Conventions

- Lua 5.1, two-space indent, comments that say why.
- A new WoW global goes in `.luacheckrc`. If lua-language-server doesn't know it either, add it to `diagnostics.globals` in `.luarc.json`.
- A new module file goes in `ForeverUtils.toc` between `Core.lua` and `Options.lua`.
- A new setting gets a default in the module's `defaults` and, if the player should control it, a widget in `BuildOptions`.

## With every player-facing change

- `README.md`: the feature's section.
- `DESCRIPTION.md`: the CurseForge project page text, written for players. It is pasted into CurseForge by hand.
- `CHANGELOG.md`: holds only the notes for the version being released, and becomes the release notes.
- `## Version` in `ForeverUtils.toc`: calendar style, `<year>.<ISO week>.<release that week>`. Bump it if the current version has already been published.

## Releasing

Pushing to `main` builds a draft GitHub release for the `.toc` version. Publishing that release uploads the zip to CurseForge. Commit, push and publish only when asked.
