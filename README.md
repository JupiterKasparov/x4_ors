# X4: Foundations - Own Radio Stations

This mod makes it possible for players to listen to their favorite music during gameplay in X4: Foundations.
Before this mod, the only way to put your music into the game was the old-school solution, frequently done by some players: namely, to mute the game, and play the music in the background.
The fully playable mod can be dwonloaded from https://www.nexusmods.com/x4foundations/mods/544

### Pros of using this mod vs the old-school solution
* In-game events have an actual effect on the music playback
* Fully compatible with the game, no need to mute anything
* Easy music change during gameplay

## Source code
This repository only contains the source code of the EXE applications. The in-game scripts can be found within the mod itself, in plain text format.
* \_\dll\_\_ directory: contains the Free Pascal source code of the X4 ORS Lua Interface DLL. Windows-only! This is necessary, because the in-game LUA engine now blacklists WinAPI FFI calls!
* \_\_editor\_\_ directory: contains the Free Pascal source code of the X4 ORS Editor. Compile with Lazarus. Windows-only!
* \_\_player\_\_ directory: contains the Free Pascal source code of the Playback Controller Application, which does the actual music playback. Compile with Lazarus for 64-bit target. Windows-only!
