library X4_ORS;

{$IF not (defined(WIN64) or (defined(LINUX) and defined(CPUX86_64)))}
  {$FATAL This addon only works on 64-bit Windows and Linux!}
{$ENDIF}

{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

{$R *.res}

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ELSE}
  BaseUnix, Unix, xlib, x,
  {$ENDIF}
  ctypes, lua;

{$IFDEF LINUX}
  {$IF not defined(shm_open)}
  function shm_open(name: PChar; oflag: cint; mode: mode_t): cint; cdecl; external 'rt' name 'shm_open';
  {$ENDIF}
  {$IF not defined(dlopen)}
  function dlopen(filename: PChar; flag: cint): Pointer; cdecl; external 'c' name 'dlopen';
  {$ENDIF}
  {$IF not defined(dlsym)}
  function dlsym(handle: Pointer; symbol: PChar): Pointer; cdecl; external 'c' name 'dlsym';
  {$ENDIF}
  {$IF not defined(dlclose)}
  function dlclose(handle: Pointer): Pointer; cdecl; external 'c' name 'dlclose';
  {$ENDIF}
{$ENDIF}

type
  UniverseID = cuint64;
  PUniverseID = ^UniverseID;

const
  SharedMemName: string = {$IFDEF LINUX}'/' + {$ENDIF}'jupiter_x4_ors_memory__main_shared_mem';
  SharedMemSize = 262144;

var
  SharedMemHandle: {$IFDEF MSWINDOWS}HANDLE{$ELSE}cint{$ENDIF};
  SharedMemBuffer: Pointer;
  factionStations: array of UniverseID;
  factionNames: array of PChar;

var
  CGetPlayerID: function: UniverseID; cdecl;
  CGetDistanceBetween: function(component1id, component2id: UniverseID): cfloat; cdecl;
  CGetNumAllFactions: function(includehidden: cbool): cuint32; cdecl;
  CGetAllFactions: function(res: PPChar; resultlen: cuint32; includehidden: cbool): cuint32; cdecl;
  CGetNumAllFactionStations: function(factionid: PChar): cuint32; cdecl;
  CGetAllFactionStations: function(res: PUniverseID; resultlen: cuint32; factionid: PChar): cuint32; cdecl;
  CGetNumStationModules: function(stationid: UniverseID; includeconstructions, includewrecks: cbool): cuint32; cdecl;

{$IFDEF LINUX}
var
  xdisplay: PDisplay;
  playerAppPid: TPid;
{$ENDIF}

// Local utilities
procedure lua_add_to_list(L: PLua_State; var index: integer);
begin
  lua_rawseti(L, -2, index + 1);
  inc(index);
end;

{$IFDEF LINUX}
procedure Sleep(ms: cint);
var
  req, rem: TimeSpec;
  res: cint;
begin
  req.tv_sec := ms div 1000;
  req.tv_nsec := (ms mod 1000) * 1000000;
  repeat
    res := FpNanosleep(@req, @rem);
    req := rem;
  until (res = 0) or (fpgeterrno <> ESysEINTR);
end;

function FindPlayerProc: TPid;
var
  dir: pDir;
  entry: pDirent;
  dirname, procName, procNameEnd: string;
  processPid, valErrCode, p: integer;
begin
  dir := FpOpendir('/proc');
  if (dir <> nil) then
     try
       try
         entry := FpReaddir(dir^);
         while (entry <> nil) do
               begin
                 dirname := StrPas(PChar(@entry^.d_name));
                 Val(dirname, processPid, valErrCode);
                 if (valErrCode = 0) then
                    begin
                      procName := fpReadLink('/proc/' + dirname + '/exe');
                      p := Pos('/x4_ors_player.elf', procName);
                      if (p > 0) then
                         begin
                           procNameEnd := Copy(procName, p, Length(procName) - p + 1);
                           if (procNameEnd = '/x4_ors_player.elf') then
                              exit(processPid);
                         end;
                    end;
                 entry := FpReaddir(dir^);
               end;
       except
         exit(0);
       end;
     finally
       FpClosedir(dir^);
     end;
  exit(0);
end;

{$ENDIF}

// Shorthand funcs
procedure internal_OpenMemBuf;
begin
  if (SharedMemBuffer = nil) then
     begin
       {$IFDEF MSWINDOWS}
       if (SharedMemHandle = HANDLE(0)) then
          SharedMemHandle := OpenFileMapping(FILE_MAP_ALL_ACCESS, WINBOOL(0), PChar(SharedMemName));
       if (SharedMemHandle <> HANDLE(0)) then
          SharedMemBuffer := MapViewOfFile(SharedMemHandle, FILE_MAP_ALL_ACCESS, 0, 0, SharedMemSize);
       {$ELSE}
       if (SharedMemHandle = -1) then
          SharedMemHandle := shm_open(PChar(SharedMemName), O_RDWR, &666);
       if (SharedMemHandle <> -1) then
          begin
            SharedMemBuffer := Fpmmap(nil, SharedMemSize, PROT_READ or PROT_WRITE, MAP_SHARED, SharedMemHandle, 0);
            if (SharedMemBuffer = MAP_FAILED) then
               SharedMemBuffer := nil;
          end;
       {$ENDIF}
     end;
end;

procedure internal_FreeMemBuf;
begin
  if (SharedMemBuffer <> nil) then
     begin
       {$IFDEF MSWINDOWS}
       UnmapViewOfFile(SharedMemBuffer);
       {$ELSE}
       Fpmunmap(SharedMemBuffer, SharedMemSize);
       {$ENDIF}
       SharedMemBuffer := nil;
     end;
  {$IFDEF MSWINDOWS}
  if (SharedMemHandle <> HANDLE(0)) then
     begin
       CloseHandle(SharedMemHandle);
       SharedMemHandle := HANDLE(0);
     end;
  {$ELSE}
  if (SharedMemHandle <> -1) then
     begin
       fpClose(SharedMemHandle);
       SharedMemHandle := -1;
     end;
  {$ENDIF}
end;

// LUA funcs
function IsMemClean(L: PLua_State): cint; cdecl;
begin
  if (SharedMemBuffer <> nil) and (PByte(SharedMemBuffer)^ = 0) then
     lua_pushboolean(L, LongBool(1))
  else
     lua_pushboolean(L, LongBool(0));
  Result := 1;
end;

function ClearMemBuf(L: PLua_State): cint; cdecl;
begin
  if (SharedMemBuffer <> nil) then
     PByte(SharedMemBuffer)^ := 0;
  Result := 0;
end;

function OpenMemBuf(L: PLua_State): cint; cdecl;
begin
  internal_OpenMemBuf;
  Result := 0;
end;

function FreeMemBuf(L: PLua_State): cint; cdecl;
begin
  internal_FreeMemBuf;
  Result := 0;
end;

function SendCommand(L: PLua_State): cint; cdecl;
var
  offset: dword;
  exeFunction: byte;
  i, j, stationCount: integer;
  playerid: UniverseID;
  numFactions: cuint32;
  currFaction: PChar;
  shortestDist, currentDist: cfloat;
  numCurrFactStations: cuint32;
  p2, p3, p4: boolean;
begin
  if (SharedMemBuffer <> nil) and (lua_gettop(L) >= 1) and (lua_isnumber(L, 1) <> LongBool(0)) then
     begin
       exeFunction := byte(lua_tointeger(L, 1)); // Param 1
       if (exeFunction = 1) then
          begin
            offset := 1;

            p2 := false;
            p3 := false;
            p4 := false;

            // Param 2: Music Volume (float)
            if (lua_gettop(L) >= 2) and (lua_isnumber(L, 2) <> LongBool(0)) then
               begin
                 PByte(SharedMemBuffer + offset)^ := 1;
                 pcfloat(SharedMemBuffer + offset + 1)^ := cfloat(lua_tonumber(L, 2));
                 inc(offset, sizeof(cfloat) + 1);
               end;

            // Param 3: Is Active Menu (bool / byte)
            if (lua_gettop(L) >= 3) and (lua_isnumber(L, 3) <> LongBool(0)) then
               begin
                 PByte(SharedMemBuffer + offset)^ := 2;
                 PByte(SharedMemBuffer + offset + 1)^ := byte(lua_tointeger(L, 3));
                 inc(offset, 2);
                 if (lua_tointeger(L, 3) <> 0) then
                    p2 := true;
               end;

            // Param 4: Can Hear Music (bool / byte)
            if (lua_gettop(L) >= 4) and (lua_isnumber(L, 4) <> LongBool(0)) then
               begin
                 PByte(SharedMemBuffer + offset)^ := 3;
                 PByte(SharedMemBuffer + offset + 1)^ := byte(lua_tointeger(L, 4));
                 inc(offset, 2);
                 if (lua_tointeger(L, 4) <> 0) then
                    p3 := true;
               end;

            // Param 5: Current Station Index (int)
            if (lua_gettop(L) >= 5) and (lua_isnumber(L, 5) <> LongBool(0)) then
               begin
                 PByte(SharedMemBuffer + offset)^ := 4;
                 pcint(SharedMemBuffer + offset + 1)^ := cint(lua_tointeger(L, 5));
                 inc(offset, sizeof(cint) + 1);
                 if (lua_tointeger(L, 5) >= 0) then
                    p4 := true;
               end;

            // Faction data
            if p2 and p3 and p4 then
               begin
                 playerid := CGetPlayerID();
                 numFactions := CGetNumAllFactions(cbool(1));
                 if (Length(factionNames) < numFactions) then
                    SetLength(factionNames, numFactions);
                 numFactions := CGetAllFactions(@factionNames[0], numFactions, cbool(1));
                 for i := 0 to numFactions - 1 do
                     begin
                       currFaction := factionNames[i];
                       numCurrFactStations := CGetNumAllFactionStations(currFaction);
                       if (Length(factionStations) < numCurrFactStations) then
                          SetLength(factionStations, numCurrFactStations);
                       numCurrFactStations := CGetAllFactionStations(@factionStations[0], numCurrFactStations, currFaction);
                       shortestDist := 10000000000.0; // 1 million km (1 billion m)
                       stationCount := 0;
                       for j := 0 to numCurrFactStations - 1 do
                           if (CGetNumStationModules(factionStations[j], cbool(0), cbool(0)) <> 0) then
                              begin
                                currentDist := CGetDistanceBetween(playerid, factionStations[j]);
                                if (currentDist < shortestDist) then
                                   shortestDist := currentDist;
                                inc(stationCount);
                              end;
                       if (stationCount > 0) and (StrLen(currFaction) > 0) then
                          begin
                            PByte(SharedMemBuffer + offset)^ := 5;
                            inc(offset);
                            Move(currFaction^, (SharedMemBuffer + offset)^, StrLen(currFaction) + 1);
                            inc(offset, StrLen(currFaction) + 1);
                            pcfloat(SharedMemBuffer + offset)^ := shortestDist;
                            inc(offset, sizeof(cfloat));
                          end;
                     end;
               end;

            // Closing param
            PByte(SharedMemBuffer + offset)^ := 0;
          end;

       // Write EXE function last
       if (exeFunction <> 2) then // Exe function 2 cannot be called! It is actually the answer provided by the EXE!
          PByte(SharedMemBuffer)^ := exeFunction;
     end;
  Result := 0;
end;

function GetAnswer(L: PLua_State): cint; cdecl;
var
  offset: dword;
  datatype: byte;
  index: integer;
begin
  lua_newtable(L);
  if (SharedMemBuffer <> nil) and (PByte(SharedMemBuffer)^ = 2) then
     begin
       index := 0;
       offset := 1;
       repeat
         datatype := PByte(SharedMemBuffer + offset)^;
         inc(offset);

         // Data identifier
         if (datatype <> 0) then
            begin
              lua_pushinteger(L, datatype);
              lua_add_to_list(L, index);
            end;

         // Rs Name
         if (datatype = 1) then
            begin
              lua_pushstring(L, PChar(SharedMemBuffer + offset));
              lua_add_to_list(L, index);
              inc(offset, StrLen(PChar(SharedMemBuffer + offset)) + 1);
            end

         // Latency
         else if (datatype = 2) then
            begin
              lua_pushinteger(L, pcint(SharedMemBuffer + offset)^);
              lua_add_to_list(L, index);
              inc(offset, sizeof(cint));
            end

         // Key
         else if (datatype = 3) then
            begin
              lua_pushinteger(L, PDWORD(SharedMemBuffer + offset)^);
              lua_add_to_list(L, index);
              inc(offset, sizeof(DWORD));
            end;
       until datatype = 0;
     end;
  Result := 1;
end;

function IsExeRunning(L: PLua_State): cint; cdecl;
{$IFDEF MSWINDOWS}
var
  appMutexHandle: HANDLE;
begin
  appMutexHandle := OpenMutex(MUTEX_ALL_ACCESS, WINBOOL(0), 'jupiter_x4_ors__program_instance');
  if (appMutexHandle <> 0) then
     begin
       CloseHandle(appMutexHandle);
       lua_pushboolean(L, LongBool(1));
     end
  else
     lua_pushboolean(L, LongBool(0));
  Result := 1;
end;
{$ELSE}
begin
  if (playerAppPid = 0) then
     playerAppPid := FindPlayerProc; // It may already be running?
  if (playerAppPid = 0) or (FpKill(playerAppPid, 0) <> 0) then
     begin
       playerAppPid := 0;
       lua_pushboolean(L, LongBool(0));
     end
  else
     lua_pushboolean(L, LongBool(1));
  Result := 1;
end;
{$ENDIF}

function IsKeyDown(L: PLua_State): cint; cdecl;
var
  vk: cint;
  {$IFDEF LINUX}
  keyState: array [0..31] of char;
  physKeyCode: TKeyCode;
  {$ENDIF}
begin
  if (lua_gettop(L) >= 1) and (lua_isnumber(L, 1) <> LongBool(0)) then
     begin
       vk := cint(lua_tointeger(L, 1));
       if (vk <> 0) then
          begin
            {$IFDEF MSWINDOWS}
            if ((GetAsyncKeyState(vk) and $8000) <> 0) then
               lua_pushboolean(L, LongBool(1))
            {$ELSE}
            if (xdisplay = nil) then
               xdisplay := XOpenDisplay(nil);
            if (xdisplay <> nil) then
               begin
                 physKeyCode := XKeysymToKeycode(xdisplay, vk);
                 if (physKeyCode <> 0) then
                    begin
                      XQueryKeymap(xdisplay, PChar(@keyState));
                      if ((ord(keyState[physKeyCode shr 3]) and (1 shl (physKeyCode and 7))) <> 0) then
                         lua_pushboolean(L, LongBool(1))
                      else
                         lua_pushboolean(L, LongBool(0));
                    end
                 else
                    lua_pushboolean(L, LongBool(0));
               end
            {$ENDIF}
            else
               lua_pushboolean(L, LongBool(0));
          end
       else
          lua_pushboolean(L, LongBool(0));
     end
  else
     lua_pushboolean(L, LongBool(0));
  Result := 1;
end;

function WinSleep(L: PLua_State): cint; cdecl;
begin
  if (lua_gettop(L) >= 1) and (lua_isnumber(L, 1) <> LongBool(0)) then
     Sleep(lua_tointeger(L, 1))
  else
     Sleep(0);
  Result := 0;
end;

function StartExe(L: PLua_State): cint; cdecl;
{$IFDEF MSWINDOWS}
const
  exename: string = 'extensions\x4_ors\bin\win64\x4_ors_player.exe';
var
  fullpath: array [0..2047] of char;
  dummy: LPSTR;
  startupInfoStruct: TStartupInfo;
  processInfoStruct: TProcessInformation;
  procExitCode: DWORD;
begin
  Result := 1;
  dummy := nil;
  ZeroMemory(@fullpath[0], Length(fullpath));
  ZeroMemory(@startupInfoStruct, sizeof(startupInfoStruct));
  ZeroMemory(@processInfoStruct, sizeof(processInfoStruct));
  startupInfoStruct.cb := sizeof(startupInfoStruct);
  if (GetFullPathName(PChar(exename), Length(fullpath), @fullpath[0], dummy) <> 0) then
     begin
       if (CreateProcess(fullpath, nil, nil, nil, BOOL(0), 0, nil, nil, startupInfoStruct, processInfoStruct) <> BOOL(0)) then
          begin
            WaitForSingleObject(processInfoStruct.hProcess, 500);
            try
              procExitCode := 259;
              while true do
                    begin
                      if (GetExitCodeProcess(processInfoStruct.hProcess, procExitCode) <> BOOL(0)) and (procExitCode = 259) then
                         begin
                           internal_OpenMemBuf;
                           if (SharedMemBuffer <> nil) then
                              begin
                                internal_FreeMemBuf;
                                lua_pushinteger(L, 1);
                                exit(1);
                              end
                           else
                              Sleep(10);
                         end
                      else
                         begin
                           lua_pushinteger(L, 0);
                           exit(1);
                         end;
                    end;
            finally
              CloseHandle(processInfoStruct.hProcess);
              CloseHandle(processInfoStruct.hThread);
            end;
          end
       else
          begin
            lua_pushinteger(L, 0);
            exit(1);
          end;
     end
  else
     begin
       lua_pushinteger(L, 0);
       exit(1);
     end;
end;
{$ELSE}
var
  currWorkDir, exePath, gamePid: string;
  exePathBuf: array [0..1023] of char;
  gamePidBuf: array [0..128] of char;
  len: integer;
  procArgs: array [0..2] of PChar;
  locProcID, tempProcPID: TPid;
  tempPipe: TFilDes;
  signalMask: sigset_t;
begin
  Result := 1;
  try
    // Exe Path
    currWorkDir := FpGetcwd;
    if (currWorkDir <> '') and (currWorkDir[Length(currWorkDir)] <> '/') then
       currWorkDir := currWorkDir + '/';
    exePath := currWorkDir + 'extensions/x4_ors/bin/linux64/x4_ors_player.elf';
    FillChar(exePathBuf, Length(exePathBuf) * SizeOf(char), #0);
    len := Length(exePath);
    if (len > (Length(exePathBuf) - 1)) or (len <= 0) then
       begin
         lua_pushinteger(L, 0);
         exit(1);
       end;
    Move(exePath[1], exePathBuf[0], len * SizeOf(char));

    // Game PID
    Str(FpGetpid, gamePid);
    FillChar(gamePidBuf, Length(gamePidBuf) * SizeOf(char), #0);
    len := Length(gamePid);
    if (len > (Length(gamePidBuf) - 1)) or (len <= 0) then
       begin
         lua_pushinteger(L, 0);
         exit(1);
       end;
    Move(gamePid[1], gamePidBuf[0], len * SizeOf(char));

    // Proc Args setup
    procArgs[0] := @exePathBuf[0];
    procArgs[1] := @gamePidBuf[0];
    procArgs[2] := nil;
    locProcID := -1;

    // Fork setup
    FpPipe(tempPipe);
    tempProcPID := FpFork;

    // We're in the context of the child within this IF block!
    if (tempProcPID = 0) then
       begin
         FpSetsid;
         FpClose(tempPipe[0]);
         locProcID := FpFork;

         // We're in the context of the child's child within this IF block
         if (locProcID = 0) then
            begin
              FpClose(tempPipe[1]);
              if (FpSigProcMask(SIG_SETMASK, nil, @signalMask) = 0) then
                 begin
                   fpSigDelSet(signalMask, SIGTERM);
                   fpSigDelSet(signalMask, SIGINT);
                   fpSigDelSet(signalMask, SIGQUIT);
                   fpSigDelSet(signalMask, SIGHUP);
                   fpSigProcMask(SIG_SETMASK, @signalMask, nil);
                 end;
              FpExecv(PChar(@exePathBuf[0]), @procArgs[0]); // We now jump to the EXE. If we're good, we won't return...
              FpExit(127);
            end;

         // We're in the context of the child again
         FpWrite(tempPipe[1], @locProcID, SizeOf(locProcID));
         FpClose(tempPipe[1]);
         FpExit(0);
       end;

    // We're in the context of the LUA again
    FpClose(tempPipe[1]);
    if (FpRead(tempPipe[0], @locProcID, SizeOf(locProcID)) <> SizeOf(locProcID)) then
       locProcID := -1;
    FpWaitPid(tempProcPID, nil, 0);
    FpClose(tempPipe[0]);

    // OK, we got the ID... now do the memory checks
    if (locProcID = -1) then
       lua_pushinteger(L, 0)
    else
       begin
         playerAppPid := locProcID;
         Sleep(500);
         while true do
               begin
                 if (FpKill(playerAppPid, 0) <> 0) then
                    begin
                      lua_pushinteger(L, 0);
                      exit(1);
                    end;
                 internal_OpenMemBuf;
                 if (SharedMemBuffer <> nil) then
                    begin
                      internal_FreeMemBuf;
                      lua_pushinteger(L, 1);
                      exit(1);
                    end
                 else
                    Sleep(10);
               end;
       end;
  except
    lua_pushinteger(L, 0);
  end;

  // If we haven't exited yet, no prcoess is started!
  lua_pushinteger(L, 0);
end;
{$ENDIF}

// LIB Cleanup
procedure CleanupLib;
begin
  internal_FreeMemBuf;
  SetLength(factionNames, 0);
  SetLength(factionStations, 0);
  {$IFDEF LINUX}
  if (xdisplay <> nil) then
     begin
       XCloseDisplay(xdisplay);
       xdisplay := nil; // Assigned when first needed
     end;
  playerAppPid := 0;
  {$ENDIF}
end;

// LIB Free
procedure FreeLib{$IFDEF MSWINDOWS}(reason: PtrInt){$ENDIF};
begin
  CleanupLib;
end;

// LUA registration
function init(L: PLua_State): cint; cdecl;
begin
  // Do a cleanup
  CleanupLib;

  // Check if all game functions could be loaded
  if (CGetPlayerID = nil) or
     (CGetDistanceBetween = nil) or
     (CGetNumAllFactions = nil) or
     (CGetAllFactions = nil) or
     (CGetNumAllFactionStations = nil) or
     (CGetAllFactionStations = nil) or
     (CGetNumStationModules = nil)
     then
        begin
          lua_pushliteral(L, 'Some necessary game functions could not be found!');
          lua_error(L);
        end
  else
        begin
          // Register LUA functions
          lua_register(L, 'X4_ORS_IsMemClean', @IsMemClean);
          lua_register(L, 'X4_ORS_ClearMemBuf', @ClearMemBuf);
          lua_register(L, 'X4_ORS_OpenMemBuf', @OpenMemBuf);
          lua_register(L, 'X4_ORS_FreeMemBuf', @FreeMemBuf);
          lua_register(L, 'X4_ORS_SendCommand', @SendCommand);
          lua_register(L, 'X4_ORS_GetAnswer', @GetAnswer);
          lua_register(L, 'X4_ORS_IsExeRunning', @IsExeRunning);
          lua_register(L, 'X4_ORS_IsKeyDown', @IsKeyDown);
          lua_register(L, 'X4_ORS_Sleep', @WinSleep);
          lua_register(L, 'X4_ORS_StartExe', @StartExe);
        end;

  // Return
  Result := 1;
end;

// MAIN
exports
  init name 'luaopen_x4_ors';

var
  modHandle: {$IFDEF MSWINDOWS}HMODULE{$ELSE}Pointer{$ENDIF};
begin
  {$IFDEF MSWINDOWS}
  DisableThreadLibraryCalls(HInstance);
  DLL_Process_Detach_Hook := @FreeLib;
  {$ELSE}
  AddExitProc(@FreeLib);
  {$ENDIF}

  // Var init
  SharedMemBuffer := nil;
  SharedMemHandle := {$IFDEF MSWINDOWS}HANDLE(0){$ELSE}-1{$ENDIF};
  SetLength(factionNames, 0);
  SetLength(factionStations, 0);
  {$IFDEF LINUX}
  xdisplay := nil;
  playerAppPid := 0;
  {$ENDIF}

  // X4 function assignment
  modHandle := {$IFDEF MSWINDOWS}GetModuleHandle(nil){$ELSE}dlopen(nil, 1){$ENDIF};
  if (modHandle <> {$IFDEF MSWINDOWS}HMODULE(0){$ELSE}nil{$ENDIF}) then
     begin
       Pointer(CGetPlayerID) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetPlayerID');
       Pointer(CGetDistanceBetween) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetDistanceBetween');
       Pointer(CGetNumAllFactions) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetNumAllFactions');
       Pointer(CGetAllFactions) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetAllFactions');
       Pointer(CGetNumAllFactionStations) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetNumAllFactionStations');
       Pointer(CGetAllFactionStations) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetAllFactionStations');
       Pointer(CGetNumStationModules) := {$IFDEF MSWINDOWS}GetProcAddress{$ELSE}dlsym{$ENDIF}(modHandle, 'GetNumStationModules');
       {$IFDEF LINUX}
       dlclose(modHandle);
       {$ENDIF}
     end
  else
     begin
       Pointer(CGetPlayerID) := nil;
       Pointer(CGetDistanceBetween) := nil;
       Pointer(CGetNumAllFactions) := nil;
       Pointer(CGetAllFactions) := nil;
       Pointer(CGetNumAllFactionStations) := nil;
       Pointer(CGetAllFactionStations) := nil;
       Pointer(CGetNumStationModules) := nil;
     end;
end.

