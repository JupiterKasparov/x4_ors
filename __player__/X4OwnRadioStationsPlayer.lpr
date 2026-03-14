program X4OwnRadioStationsPlayer;

{$IF not (defined(WIN64) or (defined(LINUX) and defined(CPUX86_64)))}
  {$FATAL This application only works on 64-bit Windows and Linux!}
{$ENDIF}

{$APPTYPE GUI}
{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

uses
    {$IFDEF MSWINDOWS}
    Windows,
    {$ELSE}
    cthreads, clocale, BaseUnix, Unix, termio,
    {$ENDIF}
    SysUtils, Classes, ctypes,
    FileUtil, strutils, fpjson,
    u_logger, u_radio, u_utils, u_manager, u_jsonmanager;

{$IFDEF LINUX}
  {$IF not defined(shm_open)}
  function shm_open(name: PChar; oflag: cint; mode: mode_t): cint; cdecl; external 'rt' name 'shm_open';
  {$ENDIF}
  {$IF not defined(shm_unlink)}
  function shm_unlink(name: PChar): cint; cdecl; external 'rt' name 'shm_unlink';
  {$ENDIF}
{$ENDIF}

const
  ProgramMutexName: string = {$IFDEF LINUX}'/tmp/' + {$ENDIF}'jupiter_x4_ors__program_instance' {$IFDEF LINUX} + '.lock'{$ENDIF};
  SharedMemName: string = {$IFDEF LINUX}'/' + {$ENDIF}'jupiter_x4_ors_memory__main_shared_mem';
  SharedMemSize = 262144;

type
  TProgramSettings = record
    Latency: integer;
    RandomizeTracks: boolean;
    LinearVolume: boolean;
    MasterLoudness: double;
    Keys: array of DWORD;
  end;

  TGameStatus = record
    CurrentStationIndex: integer;
    MusicVolume: double;   // Game setting
    IsActiveMenu: boolean; // False if the Pause Menu is active
    CanHearMusic: boolean;
  end;

var
  ProgramSettings: TProgramSettings;
  GameStatus: TGameStatus;
  Manager: TRadioStationManager;
  ClosestStationData: TFactionDistanceDataArray;
  SharedMemFile: {$IFDEF MSWINDOWS}HANDLE{$ELSE}cint{$ENDIF};
  MemoryBuffer: Pointer;

// ********************************
// HELPERS
// ********************************
{$IFDEF LINUX}
var
  parentPid: TPid = 0;
  bHasSigTerm: boolean = false;
  sigTermHandlers, sigIgnoreHandlers: sigactionrec;

procedure SigTermHandler(sig: cint; info: psiginfo; context: PSigContext); cdecl;
begin
  bHasSigTerm := true;
end;
{$ENDIF}

function IsGameRunning: boolean;
{$IFDEF MSWINDOWS}
var
  gamemutex: HANDLE;
begin
  gamemutex := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), 'EGOSOFT_X4_INSTANCE');
  Result := gamemutex <> 0;
  if Result then
     CloseHandle(gamemutex);
end;
{$ELSE}
var
  procName: string;
begin
  // If we've received SIGTERM from Steam Sandbox, quickly return false!
  if bHasSigTerm then
     exit(false);

  // If we're yet to query our parent, check it now...
  if (parentPid = 0) then
     begin
       if not TryStrToInt(ParamStr(1), parentPid) then
          exit(false);
       if (FpKill(parentPid, 0) <> 0) then
          exit(false);
       procName := fpReadLink(Format('/proc/%d/exe', [parentPid]));
       if not AnsiEndsStr('/X4', procName) then
          exit(false);
     end;

  // Check if process is running
  if (FpKill(parentPid, 0) <> 0) then
     exit(false);

  // Check existence of mutex
  if not FileExists('/tmp/EGOSOFT_X4.lock') then
     exit(false);

  // OK
  exit(true);
end;
{$ENDIF}

procedure GetMP3Data(lst: TStrings; dir: string);
var
  rec: TSearchRec;
  fn: string;
begin
  lst.Clear;
  DoDirSeparators(dir);
  dir := IncludeTrailingPathDelimiter(dir);
  if (FindFirst(dir + '*', faAnyFile, rec) = 0) then
     begin
       repeat
          if ((rec.Attr and faDirectory) = faDirectory) or (rec.Name = '.') or (rec.Name = '..') then
             continue; // Do not load directories!
          fn := dir + rec.Name;
          DoDirSeparators(fn);
          if (lst.IndexOf(fn) < 0) then
             lst.Add(fn);
       until (FindNext(rec) <> 0);
       FindClose(rec);
     end;
end;

// ********************************
// UTILS
// ********************************
procedure SendProgramData;
var
  i: integer;
  offset: dword;
  names: TStringArray;
  s: string;
begin
  offset := 1;

  // Rs Names
  try
    names := Manager.GetNameList;
    for i := 0 to High(names) do
        begin
          PByte(MemoryBuffer + offset)^ := 1; // Data type: Rs Name
          inc(offset);
          s := names[i];
          if (Length(s) > 0) then
             begin
               Move(s[1], (MemoryBuffer + offset)^, Length(s));
               inc(offset, Length(s));
             end;
          PChar(MemoryBuffer + offset)^ := #0;
          inc(offset);
        end;
  finally
    SetLength(names, 0);
  end;

  // Latency
  PByte(MemoryBuffer + offset)^ := 2; // Data type: Latency
  inc(offset);
  pcint(MemoryBuffer + offset)^ := cint(ProgramSettings.Latency);
  inc(offset, sizeof(cint));

  // Keys
  for i := 0 to High(ProgramSettings.Keys) do
      begin
        PByte(MemoryBuffer + offset)^ := 3; // Data type: Key
        inc(offset);
        PDWORD(MemoryBuffer + offset)^ := ProgramSettings.Keys[i];
        inc(offset, sizeof(DWORD));
      end;

  // Closing tag
  PByte(MemoryBuffer + offset)^ := 0;
end;

procedure ProcessGameData;
var
  offset: DWORD;
  cf: cfloat;
  cb, gamedataparam: byte;
  ci: cint;
  s: string;
begin
  // Clear records
  FillChar(GameStatus, sizeof(GameStatus), 0);
  GameStatus.CurrentStationIndex := -1;
  SetLength(ClosestStationData, 0);

  // Process data
  offset := 1;
  repeat
     gamedataparam := PByte(MemoryBuffer + offset)^;
     inc(offset);
     case gamedataparam of
           1:
             begin
               cf := pcfloat(MemoryBuffer + offset)^;
               GameStatus.MusicVolume := Clamp(cf, 0.0, 1.0);
               inc(offset, sizeof(cfloat));
             end;
           2:
             begin
               cb := PByte(MemoryBuffer + offset)^;
               GameStatus.IsActiveMenu := (cb <> 0);
               inc(offset);
             end;
           3:
             begin
               cb := PByte(MemoryBuffer + offset)^;
               GameStatus.CanHearMusic := (cb <> 0);
               inc(offset);
             end;
           4:
             begin
               ci := pcint(MemoryBuffer + offset)^;
               GameStatus.CurrentStationIndex := ci;
               inc(offset, sizeof(cint));
             end;
           5:
             begin
               s := StrPas(PChar(MemoryBuffer + offset));
               inc(offset, Length(s) + 1);
               cf := pcfloat(MemoryBuffer + offset)^;
               inc(offset, sizeof(cfloat));
               SetLength(ClosestStationData, Length(ClosestStationData) + 1);
               ClosestStationData[High(ClosestStationData)].FactionName := s;
               ClosestStationData[High(ClosestStationData)].DistanceKm := cf / 1000.0; // To get the distance in km
             end;
     end;
  until gamedataparam = 0;
end;

// ********************************
// LOADERS
// ********************************
procedure LoadRadioStation(rsData: TJSONData);
var
  slots, slotOrderBy: TJSONArray;
  rs, slot: TJSONObject;
  slotLoudness, slotDampFactor: double;
  stationName, slotURL: string;
  stationEnabled, slotIsMP3, slotIsOrdered, slotIsNotControllable: boolean;
  radioStation: TRadioStation;
  mp3List, orderList: TStrings;
  slotOwners: TStringArray;
  i, j: integer;
begin
  if (rsData = nil) or (rsData.JSONType <> jtObject) then
     exit;

  // Rs init
  rs := TJSONObject(rsData);
  stationName := Trim(GetStringSetting(rs, 'name'));
  if (stationName = '') then
     stationName := '???';
  stationEnabled := GetBooleanSetting(rs, 'enabled', true);
  if not stationEnabled then
     begin
       Log('INIT', Format('Skipping disabled radio station ''%s''!', [stationName]));
       exit;
     end;
  slots := GetListSetting(rs, 'slots');
  if (slots = nil) or (slots.Count <= 0) then
     begin
       Log('INIT', Format('Skipping radio station ''%s'' with no tracks!', [stationName]));
       exit;
     end;

  // Rs setup
  radioStation := TRadioStation.Create;
  mp3List := TStringList.Create;
  orderList := TStringList.Create;
  try
    try
      radioStation.MasterVolume := Clamp(GetFloatSetting(rs, 'masterLoudness', 1.0), 0.0, 1.0);
      radioStation.RadioStationName := stationName;
      for i := 0 to slots.Count - 1 do
          begin
            slot := TJSONObject(slots[i]);
            if (slot = nil) or (slot.JSONType <> jtObject) then
               continue;

            // Rs slot init
            slotLoudness := Clamp(GetFloatSetting(slot, 'loudness'), 0.0, 1.0);
            slotDampFactor := Clamp(GetFloatSetting(slot, 'dampFactor'), 0.0, 1.0);
            slotOwners := ParseList(GetStringSetting(slot, 'owners'));
            if not radioStation.CheckSlotOwnerListCompatibility(slotOwners) then
               begin
                 Log('INIT', Format('Radio station ''%s'' cannot load track %d, ownership collision detected!', [radioStation.RadioStationName, i + 1]));
                 continue;
               end;
            slotIsMP3 := GetBooleanSetting(slot, 'isMP3Player');
            slotURL := GetStringSetting(slot, 'url');
            if (slotURL = '') then
               continue;
            slotIsOrdered := GetBooleanSetting(slot, 'isOrdered');
            slotIsNotControllable := GetBooleanSetting(slot, 'disableUserInteraction');

            // Rs lsot load (MP3)
            if slotIsMP3 then
               begin
                 mp3List.Clear;
                 if not DirectoryExists(slotURL) then
                    begin
                      Log('INIT', Format('Radio station ''%s'' cannot load MP3 player track %d from nonexistent directory ''%s''!', [radioStation.RadioStationName, i + 1, slotURL]));
                      continue;
                    end;
                 GetMP3Data(mp3List, slotURL);
                 if slotIsOrdered then
                    begin
                      orderList.Clear;
                      slotOrderBy := TJSONArray(GetListSetting(slot, 'orderByList'));
                      if (slotOrderBy <> nil) then
                         begin
                           for j := 0 to slotOrderBy.Count - 1 do
                               begin
                                 if (slotOrderBy[j].JSONType <> jtString) then
                                    continue;
                                 orderList.Add(slotOrderBy[j].AsString);
                               end;
                           OrderListByList(mp3List, orderList);
                         end;
                    end
                 else if ProgramSettings.RandomizeTracks then
                    ShuffleList(mp3List);
                 if not radioStation.AddRadioSlot(slotOwners, mp3List, slotLoudness, slotDampFactor, slotIsNotControllable) then
                    Log('INIT', Format('Radio station ''%s'' failed to load MP3 player track %d!', [radioStation.RadioStationName, i + 1]));
               end

            // Rs slot load (single-flie or stream-based)
            else
               begin
                 if (not IsNetFile(slotURL)) and (not FileExists(slotURL)) then
                    begin
                      Log('INIT', Format('Radio station ''%s'' cannot load track %d from nonexistent file ''%s''!', [radioStation.RadioStationName, i + 1, slotURL]));
                      continue;
                    end;
                 if not  radioStation.AddRadioSlot(slotOwners, slotURL, slotLoudness, slotDampFactor) then
                    Log('INIT', Format('Radio station ''%s'' failed to load track %d!', [radioStation.RadioStationName, i + 1]));
               end;
          end;

      // Rs final check
      if not radioStation.IsValid then
         begin
           Log('INIT', Format('Radio station ''%s'' failed to load!', [radioStation.RadioStationName]));
           radioStation.Free;
         end
      else
         Manager.AddRadioStation(radioStation);
    except
      LogError(ExceptObject, ExceptAddr);
      radioStation.Free;
    end;
  finally
    mp3List.Clear;
    mp3List.Free;
    orderList.Clear;
    orderList.Free;
    SetLength(slotOwners, 0);
  end;
end;

// ********************************
// INIT, FINAL, RUN
// ********************************
procedure InitProgram;
var
  settings: TJSONObject;
  arr: TJSONArray;
  i: integer;
begin
  // Program initialization
  FillChar(GameStatus, sizeof(GameStatus), 0);
  Manager := TRadioStationManager.Create;
  SetLength(ClosestStationData, 0);
  SetLength(ProgramSettings.Keys, 0);

  // Load settings and radio stations
  settings := TJSONObject(LoadSettings(GetUserDir + 'x4_ors_settings.json'));
  if (settings <> nil) and (settings.JSONType = jtObject) then
     begin
       // Program settings
       ProgramSettings.Latency := Clamp(GetIntegerSetting(settings, 'global.maxLatency', 500), 10, 5000);
       ProgramSettings.RandomizeTracks := GetBooleanSetting(settings, 'global.randomizeTracks', true);
       ProgramSettings.LinearVolume := GetBooleanSetting(settings, 'global.linearVolumeScale');
       ProgramSettings.MasterLoudness := GetFloatSetting(settings, 'global.masterLoudness', 1.0);

       // Key bindings
       arr := GetListSetting(settings, 'global.keyBindings');
       if (arr <> nil) then
          begin
            SetLength(ProgramSettings.Keys, arr.Count);
            for i := 0 to arr.Count - 1 do
                if (arr[i].JSONType = jtNumber) then
                   begin
                     try
                       ProgramSettings.Keys[i] := arr[i].AsInteger;
                     except
                       ProgramSettings.Keys[i] := 0;
                     end;
                   end
                else
                   ProgramSettings.Keys[i] := 0;
          end;

       // Radio stations
       arr := GetListSetting(settings, 'radioStations');
       if (arr <> nil) then
          for i := 0 to arr.Count - 1 do
              LoadRadioStation(arr[i]);
     end
  else
     begin
       Log('INIT', 'Failed to load settings!');
       ProgramSettings.Latency := 1000;
       ProgramSettings.RandomizeTracks := true;
       ProgramSettings.LinearVolume := false;
       ProgramSettings.MasterLoudness := 1.0;
     end;
  if (settings <> nil) then
     settings.Free;

  // Radio Station Report
  Manager.WriteReport(GetUserDir + 'x4_ors_report.log');
end;

procedure FiniProgram;
begin
  Manager.Free;
  SetLength(ClosestStationData, 0);
  SetLength(ProgramSettings.Keys, 0);
end;

function RunProgram: boolean;
var
  currentTime, lastUpdateTime: qword;
begin
  Result := false; // -> Exit program after function return
  currentTime := GetTickCount64;
  lastUpdateTime := currentTime;

  // Initialize radio stations
  if ProgramSettings.RandomizeTracks then
     begin
       Manager.Process(-1, 0.0, nil, false, rsPlaying, currentTime);
       Manager.SetRandomPos(0.775);
       Manager.Process(-1, 0.0, nil, false, rsPaused, currentTime);
     end;

  // Event loop
  while IsGameRunning do
        begin
          currentTime := GetTickCount64;
          {$IFDEF MSWINDOWS}
          MemoryBuffer := MapViewOfFile(SharedMemFile, FILE_MAP_ALL_ACCESS, 0, 0, SharedMemSize);
          {$ELSE}
          MemoryBuffer := Fpmmap(nil, SharedMemSize, PROT_READ or PROT_WRITE, MAP_SHARED, SharedMemFile, 0);
          {$ENDIF}
          try
            case PByte(MemoryBuffer)^ of
                  1:
                    begin
                      ProcessGameData;
                      lastUpdateTime := currentTime;
                      if GameStatus.IsActiveMenu then
                         begin
                           if GameStatus.CanHearMusic then
                              Manager.Process(GameStatus.CurrentStationIndex, ProgramSettings.MasterLoudness * GameStatus.MusicVolume, @ClosestStationData, ProgramSettings.LinearVolume, rsPlaying, currentTime)
                           else
                              Manager.Process(-1, 0.0, nil, false, rsPlaying, currentTime);
                         end
                      else
                         Manager.Process(-1, 0.0, nil, false, rsPaused, currentTime);
                      PByte(MemoryBuffer)^ := 0; // Clear memory
                    end;
                  3:
                    begin
                      SendProgramData;
                      PByte(MemoryBuffer)^ := 2; // Output: Answer
                    end;
                  4:
                    begin
                      Manager.ReplayCurrTrack;
                      PByte(MemoryBuffer)^ := 0; // Clear memory
                    end;
                  5:
                    begin
                      Manager.SkipNextTrack;
                      PByte(MemoryBuffer)^ := 0; // Clear memory
                    end;
                  6:
                    begin
                      Log('MAIN', 'Reloading application...');
                      PByte(MemoryBuffer)^ := 0; // Clear memory
                      exit(true); // -> Reload program after function return
                    end;
                  7:
                    begin
                      Manager.SkipPrevTrack;
                      PByte(MemoryBuffer)^ := 0; // Clear memory
                    end;
                  else
                    begin
                      if ((currentTime - lastUpdateTime) > ProgramSettings.Latency) then
                         Manager.Process(-1, 0.0, nil, false, rsPaused, currentTime);
                      if (PByte(MemoryBuffer)^ <> 2) then
                         PByte(MemoryBuffer)^ := 0; // Only clear memory, if the script has already processed the data!
                    end;
            end;
          finally
            {$IFDEF MSWINDOWS}
            UnmapViewOfFile(MemoryBuffer);
            {$ELSE}
            Fpmunmap(MemoryBuffer, SharedMemFile);
            {$ENDIF}
          end;

          // Don't consume 100% CPU, we have to wait
          Sleep(ProgramSettings.Latency div 4);
        end;
end;

// ********************************
// MAIN
// ********************************
{$R *.res}

var
  mustRunProgram: boolean = true;
  ProgramMutexHandle: {$IFDEF MSWINDOWS} HANDLE{$ELSE}cint{$ENDIF};

begin
  // ********************************
  // Application initialization
  // ********************************
  // If the priority is too low, set it to Above Normal (so music won't freeze)
  {$IFDEF MSWINDOWS}
  if (GetPriorityClass(GetCurrentProcess) <> $8000) and (GetPriorityClass(GetCurrentProcess) <> $80) and (GetPriorityClass(GetCurrentProcess) <> $100) then
     SetPriorityClass(GetCurrentProcess, $8000);
  {$ELSE}
  if (fpGetPriority(PRIO_PROCESS, 0) > -5) then
     fpSetPriority(PRIO_PROCESS, 0, -5);

  // Handle termination signal requests
  FillChar(sigTermHandlers, SizeOf(sigTermHandlers), 0);
  sigTermHandlers.sa_handler := @SigTermHandler;
  FillChar(sigIgnoreHandlers, SizeOf(sigIgnoreHandlers), 0);
  sigIgnoreHandlers.sa_handler := sigactionhandler_t(SIG_IGN);
  FPSigaction(SIGTERM, @sigTermHandlers, nil);
  FPSigaction(SIGINT, @sigTermHandlers, nil);
  FPSigaction(SIGQUIT, @sigTermHandlers, nil);
  FPSigaction(SIGHUP, @sigIgnoreHandlers, nil);
  {$ENDIF}

  // Application setup
  randomize;
  SetAppLogFile(GetUserDir + 'x4_ors_debug.log');

  // ********************************
  // Application main part
  // ********************************
  if not IsGameRunning then
     {$IFDEF MSWINDOWS}
     MessageBox(0, 'This application is internal to the X4_ORS mod! Do not start it directly!', '', MB_OK + MB_ICONERROR)
     {$ELSE}
     begin
       if (IsATTY(Output) <> 0) then
          writeln('This application is internal to the X4_ORS mod! Do not start it directly!');
     end
     {$ENDIF}
  else
     begin
       {$IFDEF MSWINDOWS}
       ProgramMutexHandle := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), PChar(ProgramMutexName));
       if (ProgramMutexHandle = 0) then
          begin
            ProgramMutexHandle := CreateMutex(nil, BOOL(1), PChar(ProgramMutexName));
            try
              SharedMemFile := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SharedMemSize, PChar(SharedMemName));
              if (SharedMemFile <> 0) then
       {$ELSE}
       ProgramMutexHandle := FpOpen(ProgramMutexName, O_CREAT or O_RDWR, &666);
       if (ProgramMutexHandle = -1) then
          begin
            LogError('Failed to create mutex lock file!');
            ExitCode := 1;
            exit;
          end;
       if (fpFlock(ProgramMutexHandle, LOCK_EX or LOCK_NB) = 0) then
          begin
            try
              SharedMemFile := shm_open(PChar(SharedMemName), O_CREAT or O_RDWR, &666);
              if (SharedMemFile <> -1) then
                 begin
                   if (FpFtruncate(SharedMemFile, SharedMemSize) <> 0) then
                      begin
                        SharedMemFile := -1;
                        shm_unlink(PChar(SharedMemName));
                      end;
                 end;
              if (SharedMemFile <> -1) then
       {$ENDIF}
                 begin
                   try
                     while mustRunProgram do
                           try
                             InitProgram;
                             try
                               mustRunProgram := RunProgram;
                             except
                               mustRunProgram := false;
                               LogError(ExceptObject, ExceptAddr);
                               ExitCode := 2;
                             end;
                             try
                               FiniProgram;
                             except
                               mustRunProgram := false;
                               LogError(ExceptObject, ExceptAddr);
                               ExitCode := 3;
                             end;
                           except
                             mustRunProgram := false;
                             LogError(ExceptObject, ExceptAddr);
                             ExitCode := 1;
                           end;
                   finally
                     {$IFDEF MSWINDOWS}
                     CloseHandle(SharedMemFile);
                     {$ELSE}
                     FpClose(SharedMemFile);
                     shm_unlink(PChar(SharedMemName));
                     {$ENDIF}
                   end;
                 end
              else
                 begin
                   LogError(Format('Failed to setup shared memory! Error code: %d!', [{$IFDEF MSWINDOWS}GetLastError{$ELSE}fpGetErrno{$ENDIF}]));
                   ExitCode := 1;
                 end;
            finally
              {$IFDEF MSWINDOWS}
              ReleaseMutex(ProgramMutexHandle);
              CloseHandle(ProgramMutexHandle);
              {$ELSE}
              fpFlock(ProgramMutexHandle, LOCK_UN);
              FpClose(ProgramMutexHandle);
              FpUnlink(ProgramMutexName);
              {$ENDIF}
            end
          end
       else
          {$IFDEF MSWINDOWS}
          CloseHandle(ProgramMutexHandle);
          {$ELSE}
          FpClose(ProgramMutexHandle);
          {$ENDIF}
     end;
end.

