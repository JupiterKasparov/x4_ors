library X4_ORS;

{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

{$R *.res}

uses
  SysUtils, strutils, Windows, ctypes, lua;

type
  UniverseID = cuint64;
  PUniverseID = ^UniverseID;

const
  AppMutexName: string = 'jupiter_x4_ors__program_instance';
  SharedMemName: string = 'jupiter_x4_ors_memory__main_shared_mem';
  IniFileName: string = 'extensions/X4_ORS/radiostations/settings.ini';
  ExeFileName: string = 'extensions/X4_ORS/radiostations/X4OwnRadioStationsPlayer.exe';
  SharedMemSize = 262144;

var
  SharedMemHandle: HANDLE;
  SharedMemBuffer: Pointer;
  X4OrsFormatSettings: TFormatSettings;

var
  CGetPlayerID: function: UniverseID; cdecl;
  CGetDistanceBetween: function(component1id, component2id: UniverseID): cfloat; cdecl;
  CGetNumAllFactions: function(includehidden: cbool): cuint32; cdecl;
  CGetAllFactions: function(res: PPChar; resultlen: cuint32; includehidden: cbool): cuint32; cdecl;
  CGetNumAllFactionStations: function(factionid: PChar): cuint32; cdecl;
  CGetAllFactionStations: function(res: PUniverseID; resultlen: cuint32; factionid: PChar): cuint32; cdecl;
  CGetNumStationModules: function(stationid: UniverseID; includeconstructions, includewrecks: cbool): cuint32; cdecl;

// Local utilities
function local_ini_GetInt(section, key: string; defval: integer): integer;
var
  inifile: string;
begin
  inifile := IncludeTrailingPathDelimiter(GetCurrentDir) + IniFileName;
  Result := integer(GetPrivateProfileInt(PChar(section), PChar(key), WINT(defval), PChar(inifile)));
end;

// Shorthand funcs
procedure internal_OpenMemBuf;
begin
  if (SharedMemBuffer = nil) then
     begin
       if (SharedMemHandle = HANDLE(0)) then
          SharedMemHandle := OpenFileMapping(FILE_MAP_ALL_ACCESS, WINBOOL(0), PChar(SharedMemName));
       if (SharedMemHandle <> HANDLE(0)) then
          SharedMemBuffer := MapViewOfFile(SharedMemHandle, FILE_MAP_ALL_ACCESS, 0, 0, SharedMemSize);
     end;
end;

procedure internal_FreeMemBuf;
begin
  if (SharedMemBuffer <> nil) then
     begin
       UnmapViewOfFile(SharedMemBuffer);
       SharedMemBuffer := nil;
     end;
  if (SharedMemHandle <> HANDLE(0)) then
     begin
       CloseHandle(SharedMemHandle);
       SharedMemHandle := HANDLE(0);
     end;
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
function GetFactionDataString(L: PLua_State): cint; cdecl;
var
  i, j: integer;
  playerid: UniverseID;
  numFactions: cuint32;
  factionNames: array of PChar;
  currFaction: PChar;
  shortestDist, currentDist: cfloat;
  numCurrFactStations: cuint32;
  factionStations: array of UniverseID;
  answer: string;
begin
  answer := '';
  playerid := CGetPlayerID();
  numFactions := CGetNumAllFactions(cbool(1));
  SetLength(factionNames, numFactions);
  try
    numFactions := CGetAllFactions(@factionNames[0], numFactions, cbool(1));
    for i := 0 to numFactions - 1 do
        begin
          currFaction := factionNames[i];
          numCurrFactStations := CGetNumAllFactionStations(currFaction);
          SetLength(factionStations, numCurrFactStations);
          numCurrFactStations := CGetAllFactionStations(@factionStations[0], numCurrFactStations, currFaction);
          shortestDist := cfloat.MaxValue;
          for j := 0 to numCurrFactStations - 1 do
              if (CGetNumStationModules(factionStations[j], cbool(0), cbool(0)) <> 0) then
                 begin
                   currentDist := CGetDistanceBetween(playerid, factionStations[j]);
                   if (currentDist < shortestDist) then
                      shortestDist := currentDist;
                 end;
          answer := answer + Format(#10'faction_station: %s %f', [StrPas(currFaction), shortestDist], X4OrsFormatSettings);
        end;
  finally
    SetLength(factionNames, 0);
    SetLength(factionStations, 0);
  end;
  lua_pushstring(L, PChar(answer));
  Result := 1;
end;

function SendCommand(L: PLua_State): cint; cdecl;
var
  answer: string;
  i: integer;
begin
  if (SharedMemBuffer <> nil) and (lua_gettop(L) >= 1) and (lua_isstring(L, 1) <> LongBool(0)) then
     begin
       answer := StrPas(PChar(lua_tostring(L, 1)));
       if (lua_gettop(L) >= 2) then
          answer := answer + Format(#10'%s', [StrPas(PChar(lua_tostring(L, 2)))]);
       ZeroMemory(SharedMemBuffer, Length(answer) + 1);
       for i := Length(answer) downto 1 do
           PChar(SharedMemBuffer + i - 1)^ := answer[i];
     end;
  Result := 0;
end;

function GetAnswer(L: PLua_State): cint; cdecl;
var
  answer: string;
  i: integer;
  b: byte;
begin
  if (SharedMemBuffer <> nil) then
     try
       answer := '';
       for i := 0 to SharedMemSize - 1 do
           begin
             b := PByte(SharedMemBuffer + i)^;
             if (b <> 0) then
                answer := answer + chr(b)
             else
                break;
           end;
       answer := Trim(answer);

       // Hack the Key Bindings into the result string!
       if AnsiStartsStr('programdata', Trim(answer)) then
          begin
            answer := answer + Format(#10'key_binding: %d %d', [1, local_ini_GetInt('Keys', 'Modifier_1', 0)]);
            answer := answer + Format(#10'key_binding: %d %d', [2, local_ini_GetInt('Keys', 'Modifier_2', 0)]);
            answer := answer + Format(#10'key_binding: %d %d', [3, local_ini_GetInt('Keys', 'Func_PrevStation', 0)]);
            answer := answer + Format(#10'key_binding: %d %d', [4, local_ini_GetInt('Keys', 'Func_NextStation', 0)]);
            answer := answer + Format(#10'key_binding: %d %d', [5, local_ini_GetInt('Keys', 'Func_ReplayThisMP3', 0)]);
            answer := answer + Format(#10'key_binding: %d %d', [6, local_ini_GetInt('Keys', 'Func_SkipThisMP3', 0)]);
            answer := answer + Format(#10'key_binding: %d %d', [7, local_ini_GetInt('Keys', 'Func_ReloadApp', 0)]);
          end;

       // Return answer
       lua_pushstring(L, PChar(answer));

     except
       lua_pushstring(L, '');
     end
  else
     lua_pushstring(L, '');
  Result := 1;
end;

function ParseAnswer(L: PLua_State): cint; cdecl;
var
  index, tok1, tok2: integer;
  answer, dataline, tokenName, tokenValue: string;
begin
  lua_newtable(L);

  // Parse string
  if (SharedMemBuffer <> nil) and (lua_gettop(L) >= 1) and (lua_isstring(L, 1) <> LongBool(0)) then
     begin
       index := 0;
       answer := Trim(StrPas(PChar(lua_tostring(L, 1))));
       if (answer <> '') then
          repeat
            // Parse line-by-line
            tok1 := Pos(#10, answer);
            if (tok1 > 0) then
               begin
                 dataline := Trim(LeftStr(answer, tok1 - 1));
                 answer := Trim(RightStr(answer, Length(answer) - tok1));
               end
            else
               dataline := Trim(answer);

            // Process data
            tok2 := Pos(':', dataline);
            if (tok2 > 0) then
               begin
                 tokenName := Trim(LeftStr(dataline, tok2 - 1));
                 tokenValue := Trim(RightStr(dataline, Length(dataline) - tok2));
               end
            else
               begin
                 tokenName := Trim(dataline);
                 tokenValue := '';
               end;

            // Add to result list
            lua_pushstring(L, PChar(tokenName));
            lua_rawseti(L, -2, cint((index * 2) + 1));
            lua_pushstring(L, PChar(tokenValue));
            lua_rawseti(L, -2, cint((index * 2) + 2));

            // Next iteration
            inc(index);
          until (tok1 <= 0);
     end;

  // Return
  Result := 1;
end;

function IsExeRunning(L: PLua_State): cint; cdecl;
var
  appMutexHandle: HANDLE;
begin
  appMutexHandle := OpenMutex(MUTEX_ALL_ACCESS, WINBOOL(0), PChar(AppMutexName));
  if (appMutexHandle <> 0) then
     begin
       CloseHandle(appMutexHandle);
       lua_pushboolean(L, LongBool(1));
     end
  else
     lua_pushboolean(L, LongBool(0));
  Result := 1;
end;

function IsKeyDown(L: PLua_State): cint; cdecl;
var
  vk: cint;
begin
  if (lua_gettop(L) >= 1) and (lua_isnumber(L, 1) <> LongBool(0)) then
     begin
       vk := cint(lua_tointeger(L, 1));
       if ((GetAsyncKeyState(vk) and $8000) <> 0) then
          lua_pushboolean(L, LongBool(1))
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
var
  exename: string;
  fullpath: array [0..2047] of char;
  dummy: LPSTR;
  startupInfoStruct: TStartupInfo;
  processInfoStruct: TProcessInformation;
  procExitCode: DWORD;
begin
  Result := 1;
  exename := ExeFileName;
  DoDirSeparators(exename);
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
            while true do
                  begin
                    if (GetExitCodeProcess(processInfoStruct.hProcess, procExitCode) <> BOOL(0)) then
                       begin
                         if (procExitCode <> 259) then
                            begin
                              lua_pushinteger(L, 2);
                              lua_pushinteger(L, procExitCode);
                              CloseHandle(processInfoStruct.hProcess);
                              CloseHandle(processInfoStruct.hThread);
                              exit(2);
                            end
                         else
                            begin
                              internal_OpenMemBuf;
                              if (SharedMemBuffer <> nil) then
                                 begin
                                   internal_FreeMemBuf;
                                   lua_pushinteger(L, 1);
                                   CloseHandle(processInfoStruct.hProcess);
                                   CloseHandle(processInfoStruct.hThread);
                                   exit(1);
                                 end
                              else
                                 Sleep(10);
                            end;
                       end
                    else
                       begin
                         lua_pushinteger(L, 0);
                         lua_pushstring(L, 'GetExitCodeProcess');
                         lua_pushinteger(L, lua_integer(GetLastError()));
                         CloseHandle(processInfoStruct.hProcess);
                         CloseHandle(processInfoStruct.hThread);
                         exit(3);
                       end;
                  end;
          end
       else
          begin
            lua_pushinteger(L, 0);
            lua_pushstring(L, 'CreateProcess');
            lua_pushinteger(L, lua_integer(GetLastError()));
            exit(3);
          end;
     end
  else
     begin
       lua_pushinteger(L, 0);
       lua_pushstring(L, 'GetFullPathName');
       lua_pushinteger(L, lua_integer(GetLastError()));
       exit(3);
     end;
end;


// Registers funcs
function init(L: PLua_State): cint; cdecl;
begin
  // Reset declarations, if necessary
  internal_FreeMemBuf;

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
          lua_register(L, 'X4_ORS_GetFactionDataString', @GetFactionDataString);
          lua_register(L, 'X4_ORS_SendCommand', @SendCommand);
          lua_register(L, 'X4_ORS_GetAnswer', @GetAnswer);
          lua_register(L, 'X4_ORS_ParseAnswer', @ParseAnswer);
          lua_register(L, 'X4_ORS_IsExeRunning', @IsExeRunning);
          lua_register(L, 'X4_ORS_IsKeyDown', @IsKeyDown);
          lua_register(L, 'X4_ORS_Sleep', @WinSleep);
          lua_register(L, 'X4_ORS_StartExe', @StartExe);
        end;

  // Return
  Result := 1;
end;

exports
  init name 'luaopen_x4_ors';

// Library init and final
procedure FreeLib(reason: PtrInt);
begin
  internal_FreeMemBuf;
end;

var
  modHandle: HMODULE;
begin
  DLL_Process_Detach_Hook := @FreeLib;

  // Var init
  SharedMemBuffer := nil;
  SharedMemHandle := HANDLE(0);

  // Formatting init
  X4OrsFormatSettings := DefaultFormatSettings;
  X4OrsFormatSettings.DecimalSeparator := '.';
  X4OrsFormatSettings.ShortDateFormat := 'dd/mm/yyy';
  X4OrsFormatSettings.ShortTimeFormat := 'hh:nn:ss.zzz';
  X4OrsFormatSettings.LongDateFormat := 'dd/mm/yyy';
  X4OrsFormatSettings.LongTimeFormat := 'hh:nn:ss.zzz';
  X4OrsFormatSettings.DateSeparator := '/';
  X4OrsFormatSettings.TimeSeparator := ':';

  // X4 function assignment
  modHandle := GetModuleHandle(nil);
  Pointer(CGetPlayerID) := GetProcAddress(modHandle, 'GetPlayerID');
  Pointer(CGetDistanceBetween) := GetProcAddress(modHandle, 'GetDistanceBetween');
  Pointer(CGetNumAllFactions) := GetProcAddress(modHandle, 'GetNumAllFactions');
  Pointer(CGetAllFactions) := GetProcAddress(modHandle, 'GetAllFactions');
  Pointer(CGetNumAllFactionStations) := GetProcAddress(modHandle, 'GetNumAllFactionStations');
  Pointer(CGetAllFactionStations) := GetProcAddress(modHandle, 'GetAllFactionStations');
  Pointer(CGetNumStationModules) := GetProcAddress(modHandle, 'GetNumStationModules');
end.

