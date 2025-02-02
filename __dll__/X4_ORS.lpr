library X4_ORS;

{$mode objfpc}
{$H+}

{$R *.res}

uses
  lua, lualib, Windows, ctypes;

// Shorthand funcs
function internal_GetSharedMemHandle: HANDLE;
begin
  Result := OpenFileMapping(FILE_MAP_ALL_ACCESS, WINBOOL(0), 'jupiter_x4_ors_memory__main_shared_mem');
end;

function internal_GetMemBuf(shmem: HANDLE): Pointer;
begin
  Result := MapViewOfFile(shmem, FILE_MAP_ALL_ACCESS, 0, 0, 262144)
end;

// LUA funcs
function IsMemOK(L: PLua_State): cint; cdecl;
var
  shmem: HANDLE;
  buf: Pointer;
begin
  shmem := internal_GetSharedMemHandle;
  if (shmem <> HANDLE(0)) then
     begin
       buf := internal_GetMemBuf(shmem);
       if (buf <> nil) then
          begin
            UnmapViewOfFile(buf);
            lua_pushboolean(L, LongBool(1));
          end
       else
          lua_pushboolean(L, LongBool(0));
       CloseHandle(shmem);
     end
  else
     lua_pushboolean(L, LongBool(0));
  Result := 1;
end;

function FreeMemBuf(L: PLua_State): cint; cdecl;
var
  shmem: HANDLE;
  buf: Pointer;
begin
  shmem := internal_GetSharedMemHandle;
  if (shmem <> HANDLE(0)) then
     begin
       buf := internal_GetMemBuf(shmem);
       if (buf <> nil) then
          begin
            PByte(buf)^ := 0;
            UnmapViewOfFile(buf);
          end;
       CloseHandle(shmem);
     end
  else;
  Result := 0;
end;

function SendCommand(L: PLua_State): cint; cdecl;
var
  shmem: HANDLE;
  buf: Pointer;
  answer: string;
  i: integer;
begin
  shmem := internal_GetSharedMemHandle;
  if (shmem <> HANDLE(0)) then
     try
       buf := internal_GetMemBuf(shmem);
       if (buf <> nil) then
          try
            if (lua_gettop(L) >= 1) and (lua_isstring(L, 1) <> LongBool(0)) then
               begin
                 answer := StrPas(PChar(lua_tostring(L, 1)));
                 ZeroMemory(buf, Length(answer) + 1);
                 for i := Length(answer) downto 1 do
                     PChar(buf + i - 1)^ := answer[i];
               end;
          finally
            UnmapViewOfFile(buf);
          end;
     finally
       CloseHandle(shmem);
     end;
  Result := 0;
end;

function GetAnswer(L: PLua_State): cint; cdecl;
var
  shmem: HANDLE;
  buf: Pointer;
  answer: string;
  i: integer;
  b: byte;
begin
  shmem := internal_GetSharedMemHandle;
  if (shmem <> HANDLE(0)) then
     try
       buf := internal_GetMemBuf(shmem);
       if (buf <> nil) then
          try
            if (PByte(buf)^ <> 0) then
               begin
                 answer := '';
                 for i := 0 to 262143 do
                     begin
                       b := PByte(buf + i)^;
                       if (b <> 0) then
                          answer := answer + chr(b)
                       else
                          break;
                     end;
                 lua_pushstring(L, PChar(answer));
               end
            else
               lua_pushstring(L, '');
          finally
            UnmapViewOfFile(buf);
          end
       else
          lua_pushstring(L, '');
     finally
       CloseHandle(shmem);
     end
  else
     lua_pushstring(L, '');
  Result := 1;
end;

function IsExeRunning(L: PLua_State): cint; cdecl;
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

function IsKeyDown(L: PLua_State): cint; cdecl;
var
  vk: lua_Integer;
begin
  if (lua_gettop(L) >= 1) and (lua_isnumber(L, 1) <> LongBool(0)) then
     begin
       vk := lua_tointeger(L, 1);
       if ((GetAsyncKeyState(cint(vk)) and $8000) <> 0) then
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
  fullpath: array [0..2047] of char;
  dummy: LPSTR;
  startupInfoStruct: TStartupInfo;
  processInfoStruct: TProcessInformation;
  procExitCode: DWORD;
  shmem: HANDLE;
begin
  dummy := nil;
  ZeroMemory(@fullpath[0], Length(fullpath));
  ZeroMemory(@startupInfoStruct, sizeof(startupInfoStruct));
  ZeroMemory(@processInfoStruct, sizeof(processInfoStruct));
  startupInfoStruct.cb := sizeof(startupInfoStruct);
  if (GetFullPathName('extensions/X4_ORS/radiostations/X4OwnRadioStationsPlayer.exe', Length(fullpath), @fullpath[0], dummy) <> 0) then
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
                              shmem := internal_GetSharedMemHandle;
                              if (shmem <> HANDLE(0)) then
                                 begin
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
            Result := 3;
          end;
     end
  else
     begin
       lua_pushinteger(L, 0);
       lua_pushstring(L, 'GetFullPathName');
       lua_pushinteger(L, lua_integer(GetLastError()));
       Result := 3;
     end;
end;


// Registers funcs
function luaopen_x4ors(L: PLua_State): cint; cdecl;
begin
  lua_register(L, 'X4_ORS_IsMemOK', @IsMemOK);
  lua_register(L, 'X4_ORS_FreeMemBuf', @FreeMemBuf);
  lua_register(L, 'X4_ORS_SendCommand', @SendCommand);
  lua_register(L, 'X4_ORS_GetAnswer', @GetAnswer);
  lua_register(L, 'X4_ORS_IsExeRunning', @IsExeRunning);
  lua_register(L, 'X4_ORS_IsKeyDown', @IsKeyDown);
  lua_register(L, 'X4_ORS_Sleep', @WinSleep);
  lua_register(L, 'X4_ORS_StartExe', @StartExe);
  Result := 1;
end;

exports
  luaopen_x4ors;
end.

