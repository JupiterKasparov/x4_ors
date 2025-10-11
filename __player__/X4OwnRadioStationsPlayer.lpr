program X4OwnRadioStationsPlayer;

{$IFNDEF WIN64}
  {$ERROR This application will only work on 64-bit Windows!}
{$ENDIF}

{$APPTYPE GUI}
{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

uses
    Windows, SysUtils, Classes, ctypes,
    FileUtil, IniFiles, strutils,
    u_logger, u_radio, u_utils, u_manager;

const
  ProgramMutexName: string = 'jupiter_x4_ors__program_instance';
  SharedMemName: string = 'jupiter_x4_ors_memory__main_shared_mem';
  SharedMemSize = 262144;

type
  TProgramSettings = record
    Latency: integer;
    RandomizeTracks: boolean;
    NoOnlineStreams: boolean;
    LinearVolume: boolean;
    MasterLoudness: double;
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
  Settings: TIniFile;
  SharedMemFile: HANDLE;
  MemoryBuffer: Pointer;

// ********************************
// HELPERS
// ********************************
function IsGameRunning: boolean;
var
  gamemutex: HANDLE;
begin
  gamemutex := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), 'EGOSOFT_X4_INSTANCE');
  Result := gamemutex <> 0;
  if Result then
     CloseHandle(gamemutex);
end;

procedure GetMP3Data(lst: TStrings; dir: string);
var
  rec: TSearchRec;
  fn: string;
begin
  lst.Clear;
  dir := ExcludeTrailingPathDelimiter(dir);
  if (FindFirst(Format('%s/*', [dir]), faAnyFile, rec) = 0) then
     begin
       repeat
          if ((rec.Attr and faDirectory) = faDirectory) or (rec.Name = '.') or (rec.Name = '..') then
             continue; // Do not load directories!
          fn := Format('%s/%s', [dir, rec.Name]);
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
  i, j: integer;
  offset: dword;
  names: TStringArray;
begin
  offset := 1;

  // Rs Names
  try
    names := Manager.GetNameList;
    for i := 0 to High(names) do
        begin
          PByte(MemoryBuffer + offset)^ := 1; // Data type: Rs Name
          inc(offset);
          for j := 1 to names[i].Length do
              begin
                PChar(MemoryBuffer + offset)^ := names[i][j];
                inc(offset, sizeof(char));
              end;
          PChar(MemoryBuffer + offset)^ := #0;
          inc(offset, sizeof(char));
        end;
  finally
    SetLength(names, 0);
  end;

  // Latency
  PByte(MemoryBuffer + offset)^ := 2; // Data type: Latency
  inc(offset);
  pcint(MemoryBuffer + offset)^ := cint(ProgramSettings.Latency); // Data tyoe: Latency
  inc(offset, sizeof(cint));

  // Closing tag
  PByte(MemoryBuffer + offset)^ := 0;
end;

procedure ProcessGameData;
var
  offset: dword;
  cf: cfloat;
  cb, gamedataparam: byte;
  ci: cint;
  c: char;
  s: string;
begin
  offset := 1;

  // Clear records
  ZeroMemory(@GameStatus, sizeof(GameStatus));
  GameStatus.CurrentStationIndex := -1;
  SetLength(ClosestStationData, 0);

  // Process data
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
               s := '';
               repeat
                  c := PChar(MemoryBuffer + offset)^;
                  if (c <> #0) then
                     s := s + c;
                  inc(offset, sizeof(char));
               until c = #0;
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
procedure LoadRadioStation(index: integer);
var
  radio: TRadioStation;
  i, slotCount: integer;
  slotFileName: string;
  slotOwners: TStringArray;
  mp3List: TStrings;
  loudFactor, dampFactor: double;
  mp3FeatureSupport: boolean;
begin
  radio := TRadioStation.Create;
  mp3List := TStringList.Create;

  // Radio station properties
  try
    try
      mp3FeatureSupport := false;
      radio.RadioStationName := ReadStringSetting(Settings, Format('Radio_%d.RadioText', [index]), '-- NONAME --');
      slotCount := ReadIntSetting(Settings, Format('Radio_%d.SlotCount', [index]), 0);
      if (slotCount = 0) then
         begin
           // Single-slot
           radio.MasterVolume := ReadFloatSetting(Settings, Format('Radio_%d.LoudnessFactor', [index]), 0.0);
           slotFileName := ReadStringSetting(Settings, Format('Radio_%d.FileName', [index]), '');
           slotOwners := ParseList(ReadStringSetting(Settings, Format('Radio_%d.Owner', [index]), ''));
           dampFactor := Clamp(ReadFloatSetting(Settings, Format('Radio_%d.DampeningFactor', [index]), 0.0), 0.0, 1.0);
           if (slotFileName = '') or (not IsNetFile(slotFileName)) and (not FileExists(slotFileName) and (not DirectoryExists(slotFileName))) then
              Log('INIT', Format('Radio station file or directory ''%s'' does not exist!', [slotFileName]))
           else if IsNetFile(slotFileName) and ProgramSettings.NoOnlineStreams then
              Log('INIT', Format('Ignoring online stream ''%s''...', [slotFileName]))
           else if not radio.CheckSlotOwnerListCompatibility(slotOwners) then
              Log('INIT', Format('Ownership collision detected, radio station %d (''%s'') will be ignored!', [index, radio.RadioStationName]))
           else
              begin
                if (ReadIntSetting(Settings, Format('Radio_%d.IsMP3', [index]), 0) <> 0) then
                   begin
                     if (Length(slotOwners) = 0) then
                        mp3FeatureSupport := true;
                     GetMP3Data(mp3List, slotFileName);
                     if (ReadIntSetting(Settings, Format('Radio_%d.Ordered', [index]), 0) <> 0) then
                        OrderListByFile(mp3List, Format('radio_%d_order.lst', [index]))
                     else if ProgramSettings.RandomizeTracks then
                        ShuffleList(mp3List);
                     if not radio.AddRadioSlot(slotOwners, mp3List, 1.0, dampFactor) then
                        Log('INIT', Format('Failed to load MP3 Player radio station %d (''%s'')!', [index, radio.RadioStationName]));
                   end
                else if not radio.AddRadioSlot(slotOwners, slotFileName, 1.0, dampFactor) then
                   Log('INIT', Format('Failed to load radio station %d (''%s'')!', [index, radio.RadioStationName]));
              end;
           SetLength(slotOwners, 0);
         end
      else
         begin
           // Multi-slot
           radio.MasterVolume := ReadFloatSetting(Settings, Format('Radio_%d.MasterLoudnessFactor', [index]), 0.0);
           for i := 1 to slotCount do
               begin
                 slotFileName := ReadStringSetting(Settings, Format('Radio_%d.SlotFileName_%d', [index, i]), '');
                 slotOwners := ParseList(ReadStringSetting(Settings, Format('Radio_%d.SlotOwner_%d', [index, i]), ''));
                 loudFactor := Clamp(ReadFloatSetting(Settings, Format('Radio_%d.SlotLoudnessFactor_%d', [index, i]), 0.0), 0.0, 1.0);
                 dampFactor := Clamp(ReadFloatSetting(Settings, Format('Radio_%d.SlotDampeningFactor_%d', [index, i]), 0.0), 0.0, 1.0);
                 if (slotFileName = '') or (not IsNetFile(slotFileName)) and (not FileExists(slotFileName) and (not DirectoryExists(slotFileName))) then
                    Log('INIT', Format('Slot file or directory ''%s'' does not exist!', [slotFileName]))
                 else if IsNetFile(slotFileName) and ProgramSettings.NoOnlineStreams then
                    Log('INIT', Format('Ignoring online stream ''%s''...', [slotFileName]))
                 else if not radio.CheckSlotOwnerListCompatibility(slotOwners) then
                    Log('INIT', Format('Ownership collision detected, slot %d of radio station %d (''%s'') will be ignored!', [i, index, radio.RadioStationName]))
                 else
                    begin
                      if (ReadIntSetting(Settings, Format('Radio_%d.SlotIsMP3_%d', [index, i]), 0) <> 0) then
                         begin
                           GetMP3Data(mp3List, slotFileName);
                           if (ReadIntSetting(Settings, Format('Radio_%d.SlotOrdered_%d', [index, i]), 0) <> 0) then
                              OrderListByFile(mp3List, Format('radio_%d_slot_%d_order.lst', [index, i]))
                           else if ProgramSettings.RandomizeTracks then
                              ShuffleList(mp3List);
                           if not radio.AddRadioSlot(slotOwners, mp3List, loudFactor, dampFactor) then
                              Log('INIT', Format('Failed to load MP3 Player slot %d of radio station %d (''%s'')!', [i, index, radio.RadioStationName]));
                         end
                      else if not radio.AddRadioSlot(slotOwners, slotFileName, loudFactor, dampFactor) then
                         Log('INIT', Format('Failed to load slot %d of radio station %d (''%s'')!', [i, index, radio.RadioStationName]));
                    end;
                 SetLength(slotOwners, 0);
               end;
         end;
      // Register radio station
      if radio.IsValid then
         Manager.AddRadioStation(radio, mp3FeatureSupport)
      else
         begin
           Log('INIT', Format('Radio station %d (''%s'') failed to load!', [index, radio.RadioStationName]));
           radio.Free;
         end;
      radio := nil;
    except
      if Assigned(radio) then
         radio.Free;
      raise;
    end;
  finally
    SetLength(slotOwners, 0);
    mp3List.Clear;
    mp3List.Free;
  end;
end;

procedure LoadMP3Station;
var
  radio: TRadioStation;
  mp3List: TStrings;
  owners: TStringArray;
begin
  SetLength(owners, 0);
  mp3List := TStringList.Create;
  radio := TRadioStation.Create;
  try
    try
      GetMP3Data(mp3List, 'mp3');
      if ProgramSettings.RandomizeTracks then
         ShuffleList(mp3List);
      radio.RadioStationName := ReadStringSetting(Settings, 'Radio_MP3.RadioText', '-- NONAME (MP3) --');
      radio.MasterVolume := Clamp(ReadFloatSetting(Settings, 'Radio_MP3.LoudnessFactor', 0.0), 0.0, 1.0);
      radio.AddRadioSlot(owners, mp3List, 1.0, 1.0);
      if radio.IsValid then
         Manager.AddRadioStation(radio, true)
      else
         begin
           Log('INIT', 'Failed to load the MP3 Player radio station!');
           radio.Free;
         end;
      radio := nil;
    except
      if Assigned(radio) then
         radio.Free;
      raise;
    end;
  finally
    SetLength(owners, 0);
    mp3List.Clear;
    mp3List.Free;
  end;
end;

// ********************************
// INIT, FINAL, RUN
// ********************************
procedure InitProgram;
var
  i: integer;
begin
  // Program initialization
  ZeroMemory(@GameStatus, sizeof(GameStatus));
  Manager := TRadioStationManager.Create;
  SetLength(ClosestStationData, 0);
  Settings := TIniFile.Create('settings.ini');

  // Global settings
  ProgramSettings.Latency := Clamp(ReadIntSetting(Settings, 'Global.Latency', 1000), 10, 5000);
  ProgramSettings.RandomizeTracks := (ReadIntSetting(Settings, 'Global.RandomizeTracks', 0) <> 0);
  ProgramSettings.NoOnlineStreams := (ReadIntSetting(Settings, 'Global.NoOnlineStreams', 0) <> 0);
  ProgramSettings.LinearVolume := (ReadIntSetting(Settings, 'Global.UseLinearVolume', 0) <> 0);
  ProgramSettings.MasterLoudness := Clamp(ReadFloatSetting(Settings, 'Global.LoudnessFactor', 1.0), 0.0, 1.0);

  // Radio stations
  for i := 1 to max(0, ReadIntSetting(Settings, 'Global.NumberOfStations', 0)) do
      LoadRadioStation(i);

  // Dedicated MP3 player radio station
  if (ReadIntSetting(Settings, 'Radio_MP3.Enabled', 0) <> 0) then
     LoadMP3Station;

  // Radio Station Report
  if (not NoLog) then
     Manager.WriteReport('x4_ors_report.log');
end;

procedure FiniProgram;
begin
  Manager.Free;
  SetLength(ClosestStationData, 0);
  Settings.Free;
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
          MemoryBuffer := MapViewOfFile(SharedMemFile, FILE_MAP_ALL_ACCESS, 0, 0, SharedMemSize);
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
            UnmapViewOfFile(MemoryBuffer);
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
  exeFilePath: array [0..32767] of char = '';
  i: integer;
  mustRunProgram: boolean;
  ProgramMutexHandle: HANDLE;

begin
  // ********************************
  // Application initialization
  // ********************************
  // Set working directory to real current directory (files must be accessible)
  GetModuleFileName(GetModuleHandle(nil), @exeFilePath, 32767);
  SetCurrentDir(ExtractFilePath(StrPas(exeFilePath)));

  // If the priority is too low, set it to Above Normal (so music won't freeze)
  if (GetPriorityClass(GetCurrentProcess) <> $8000) and (GetPriorityClass(GetCurrentProcess) <> $80) and (GetPriorityClass(GetCurrentProcess) <> $100) then
     SetPriorityClass(GetCurrentProcess, $8000);

  // Application main initialization
  randomize;
  mustRunProgram := true;
  for i := 1 to ParamCount do
      if (LowerCase(ParamStr(i)) = '-nolog') then
         NoLog := true;

  // ********************************
  // Application main part
  // ********************************
  if not IsGameRunning then
     MessageBox(0, 'This application is internal to the ''X4: Foundations - Own Radio Stations'' mod. Do not start it directly!', '', MB_OK + MB_ICONERROR)
  else
     begin
       ProgramMutexHandle := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), PChar(ProgramMutexName));
       if (ProgramMutexHandle = 0) then
          begin
            ProgramMutexHandle := CreateMutex(nil, BOOL(1), PChar(ProgramMutexName));
            try
              SharedMemFile := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SharedMemSize, PChar(SharedMemName));
              if (SharedMemFile <> 0) then
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
                     CloseHandle(SharedMemFile);
                   end;
                 end
              else
                 begin
                   LogError(Format('Failed to setup shared memory! Error code: %d!', [GetLastError]));
                   ExitCode := 1;
                 end;
            finally
              ReleaseMutex(ProgramMutexHandle);
              CloseHandle(ProgramMutexHandle);
            end
          end
       else
          CloseHandle(ProgramMutexHandle);
     end;
end.

