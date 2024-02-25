# X4: Foundations - Own Radio Stations

This mod makes it possible for players to listen to their favorite music during gameplay in X4: Foundations.
Before this mod, the only way (the old-school) to do this was to mute the game, and start Winamp (or similar program) in the background.
The fully playable mod can be dwonloaded from https://www.nexusmods.com/x4foundations/mods/544

### Pros of using this mod vs the old-school solution
* In-game happenings affect the music (eg. speech and player state changes)
* The game doesn't need to be muted
* Easy music change during gameplay (the mod uses hotkeys, instead of requiring the user to Alt-Tab out of the game)

## Source code
This repository contains the full source code of the mod.
* \_\_lua\_\_ directory: contains the the in-game LUA script (same as in the actually playable mod), which manages the Playback Controller Application, keeps the game background music muted, and hooks the X4 Sound Options menu. Windows-only!
* \_\_md\_\_ directory: contains the the in-game X4: Foundations Mission Director script (same as in the actually playable mod), which triggers the LUA script, to keep the mod operational; and also allows the user to change the key bindings from the Extension Options (SN Mod Support APIs) menu.
* \_\_player\_\_ directory: contains the Free Pascal source code of the Playback Controller Application, which does the actual music playback. Compile with Lazarus for 64-bit target. Windows-only!
