# X4: Foundations - Own Radio Stations

This mod makes it possible for players to listen to their favorite music during gameplay in X4: Foundations.
Before this mod, the only way to put your music into the game was the old-school solution, frequently done by some players: namely, to mute the game, and play the music in the background.
The fully playable mod can be dwonloaded from https://www.nexusmods.com/x4foundations/mods/544

### Pros of using this mod vs the old-school solution
* In-game events have an actual effect on the music playback
* Fully compatible with the game, no need to mute anything
* Easy music change during gameplay


## Source code
This repository contains the source codes for the executable binary files only. The in-game scripts are available in the mos in their pure text form.
* \_\_dll\_\_ directory: contains the Free Pascal source code of the X4 ORS Lua Interface DLL.
* \_\_editor\_\_ directory: contains the Free Pascal source code of the X4 ORS Editor.
* \_\_player\_\_ directory: contains the Free Pascal source code of the Playback Controller Application, which does the actual music playback.

### Compiling the source code
You can compile the source code with Lazarus 4.2 and FPC 3.2.2 with x86_64 support.
These binaries only work on x86_64 Windows and Linux. If Lazarus warns you about missing FPC for the current target, just ignore the error and switch to the other target in the Project Options _(I used two different Lazarus installations on a dual-boot PC to compile the binaries for the two targets)_.

#### Compiling for Linux
For Linux, the compilation process is not as straightforward, as in Windows, though I tried to keep the Linux part easily compileable, avoiding exotic units.
* The Interface DLL requires X11 and luajit
  1) find the `libluajit-5.1.so.2` in the X4 directory or its sub-directory, and copy it into the source code directory of the Interface DLL
  2) execute the `ln -s ./libluajit-5.1.so.2 ./libluajit-5.1.so` command; this creates a symlink for the linker to understand (the linker will still link the correct file though)
  3) compile the project
* The Editor requires X11 and GTK2
  1) if the LCL widgetset is not GTK2 for you, either change it to GTK2, or rewrite the GTK2 code in `u_keyeditor` and the Linux-only beautifier code in `u_osutuils`
  2) compile the project
* The Playback Controller Application requires BASS
  1) obtain the `libbass.so` from the downloadable mod package, or from the Un4Seen BASS homepage, and copy it into the source code directory of the Playback Controller Application
  2) compile the project
