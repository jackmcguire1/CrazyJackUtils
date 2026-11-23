# ForeverUtils v2026.48.1

Fixes for the marker coming off and for errors in dungeons, plus reordering your find list and a history of what you've found.

## Fixed

- **The marker no longer comes off when you press the macro again.** Pressing it a second time on the mob it had already marked used to remove the marker. The macro now clears the marker and sets it again, so it stays.
- **Errors in dungeons.** In instances the game withholds some unit names from addons, and Target Finder mishandled them, which could raise so many errors that the game offered to disable your addons. It now skips those units.
- **One problem can't flood you with errors.** If something in ForeverUtils does go wrong, it's skipped and noted. You get one line in chat, and `/fu errors` shows what happened.

## New

- **Reorder your find list.** Each mob in the `/tf` window has up and down arrows. The macro tries mobs from the top, so move the one you most want to the top.
- **History.** The window has a **History** section listing the last ten mobs you put on your find list, newest first. Click one to find it again.

## Changed

- **About three mobs fit in the macro** now, down from three or four, because keeping the marker on takes an extra line. The window is slightly wider to make room for the arrows.
