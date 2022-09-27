# x4_ors
X4: Foundations - Own Radio Stations

This is a mod for the X4: Foundations game. Its primary purpose is, to play your favorite music, as if it were playing in some kind of in-game radio station.
To keep things easy and maintainable, the mod consists of the in-game script (MD + LUA), and a separate playback controller application, which communicates with the in-game LUA script, via shared memory.
The EXE uses bass.dll to play music, and so it's Windows-only. The LUA script uses FFI to call Windows functions.

The EXE can be produced by compiling its source code with Lazarus/FPC. It's a 64-bit app!

The following content is available from this GitHub repository:
* 'Rel' directory: the full release. It can also be downloaded from Nexus Mods, in a ZIP.
* '_player' directory: source code. Use 64-bit Lazarus, to compile the EXE.

