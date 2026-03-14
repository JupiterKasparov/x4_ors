# X4: Foundations - Own Radio Stations

This mod makes it possible for players to listen to their gavorite music in X4: Foundations.
It solves the problem of "muting the game and listening to music in the background" by integrating a custom-made music player solution into the game.
The fully playable mod can be downloaded from https://www.nexusmods.com/x4foundations/mods/544

### Features
* Gameplay affects the music playback
* Fully compatible with the game, no need for complex modding tools and hacks, no mod incompatibilities
* Direct user control in music playback, no Alt-Tab required


## Source code
This repository contains the source codes only for the executable binary files. The in-game scripts are available in the mod in their pure text form.
* \_\_dll\_\_ directory: contains the Free Pascal source code of the X4 ORS Lua Interface DLL.
* \_\_editor\_\_ directory: contains the Free Pascal source code of the X4 ORS Editor.
* \_\_player\_\_ directory: contains the Free Pascal source code of the Playback Controller Application, which does the actual music playback.

### Compiling the source code
You can compile the source code with Lazarus 4.2 and FPC 3.2.2 with x86_64 support.
These binaries only work on x86_64 Windows and Linux. If Lazarus warns you about missing FPC for the current target, just ignore the error _(I used two separate Lazarus installations on a dual-boot PC to compile the binaries for the two targets)_.
Open the LPI files with Lazarus.

#### Compiling for Linux
For Linux, the compilation process is not as straightforward, as in Windows, though thanks to my careful preparations (ie. no special settings, no exotic units), even Linux compilation shall be easy.
* The Interface DLL requires X11 and luajit
  1) obtain the `libluajit-5.1.so.2` from the X4 directory _(usually in the `lib` subfolder)_, and copy it into the source code directory of the Interface DLL
  2) execute the `ln -s ./libluajit-5.1.so.2 ./libluajit-5.1.so` command; this creates a symlink for the linker to understand (the linker will still link to the correct file)
  3) compile the project
* The Editor requires X11 and GTK2
  1) set the LCL widgetset to GTK2 (if not already) and install the GTK2 packages (if not present), OR, rewrite the GTK2 code in `u_keyeditor` and the Linux-only beautifier code in `u_osutils`
  2) compile the project
* The Playback Controller Application requires BASS
  1) obtain the `libbass.so` from the downloadable mod package, or from the Un4Seen BASS homepage, and copy it into the source code directory of the Playback Controller Application
  2) compile the project
