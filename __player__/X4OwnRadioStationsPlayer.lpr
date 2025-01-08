program X4OwnRadioStationsPlayer;

{$APPTYPE GUI}
{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

uses
    Windows, SysUtils, Classes,
    Math, IniFiles, strutils,
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

  TKeyBinding = record
    IniSettingName: string;
    Key: integer;
  end;

var
  ProgramSettings: TProgramSettings;
  GameStatus: TGameStatus;
  KeyBindings: array [1..7] of TKeyBinding =
    (
     (IniSettingName: 'Keys.Modifier_1'; Key: 0),
     (IniSettingName: 'Keys.Modifier_2'; Key: 0),
     (IniSettingName: 'Keys.Func_PrevStation'; Key: 0),
     (IniSettingName: 'Keys.Func_NextStation'; Key: 0),
     (IniSettingName: 'Keys.Func_ReplayThisMP3'; Key: 0),
     (IniSettingName: 'Keys.Func_SkipThisMP3'; Key: 0),
     (IniSettingName: 'Keys.Func_ReloadApp'; Key: 0)
    );
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

procedure GetMP3Data(lst: TStrings);
const
  masks: array [0..6] of string = ('mp3/*.wav', 'mp3/*.wave', 'mp3/*.ogg', 'mp3/*.aiff', 'mp3/*.mp1', 'mp3/*.mp2', 'mp3/*.mp3');
var
  rec: TSearchRec;
  i: integer;
  fn: string;
begin
  lst.Clear;
  for i := 0 to High(masks) do
      if (FindFirst(masks[i], faAnyFile, rec) = 0) then
         begin
          repeat
            fn := Format('mp3/%s', [rec.Name]);
            if (lst.IndexOf(fn) < 0) then
               lst.Add(fn);
          until (FindNext(rec) <> 0);
          FindClose(rec);
         end;
end;

// ********************************
// UTILS
// ********************************

procedure SendData(answerType, answerText: string; mem: Pointer);
var
  answer: string;
  i: integer;
begin
  answer := answerType + #10 + answerText;

  // This construct will copy the answer to the memory backwards, so the LUA script won't try to access the data until it's fully copied
  ZeroMemory(mem, Length(answer) + 1);
  for i := Length(answer) downto 1 do
      PChar(mem + i - 1)^ := answer[i];
end;

function ProcessGameData: integer;
var
  exefunction, data, dataline, tokenName, tokenValue, tokenName2, tokenValue2, answer: string;
  i, tok1, tok2, tok3: integer;
  f: double;
  firstline: boolean;
  rsnames: TStringArray;
begin
  Result := 0; // No heartbeat
  data := Trim(StrPas(PChar(MemoryBuffer)));
  if (data <> '') then
     begin
       exefunction := '';
       firstline := true;
       repeat
         // Line-by-line processing
         tok1 := Pos(#10, data);
         if (tok1 > 0) then
            begin
              dataline := Trim(LeftStr(data, tok1 - 1));
              data := Trim(RightStr(data, Length(data) - tok1));
            end
         else
            dataline := Trim(data);
         if (exefunction = '') then
            exefunction := dataline;
         case LowerCase(exefunction) of
               'gamedata':
                 begin
                   Result := 1; // Heartbeat signal

                   // Cleanup data structures before starting to work with them
                   if firstline then
                      begin
                        firstline := false;
                        ZeroMemory(@GameStatus, sizeof(GameStatus));
                        GameStatus.CurrentStationIndex := -1;
                        SetLength(ClosestStationData, 0);
                        continue;
                      end;

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
                   case LowerCase(tokenName) of
                         'music_volume':
                           begin
                             if TryStrToInt(tokenValue, i) then
                                GameStatus.MusicVolume := min(1.0, max(0.0, i / 100.0))
                             else
                                begin
                                  Log('READ DATA', Format('Cannot convert MusicVolume property (''%s'') to int! Assuming zero!', [tokenValue]));
                                  GameStatus.MusicVolume := 0.0;
                                end;
                           end;
                         'is_active_menu':
                           begin
                             if TryStrToInt(tokenValue, i) then
                                GameStatus.IsActiveMenu := (i <> 0)
                             else
                                begin
                                  Log('READ DATA', Format('Cannot convert IsActiveMenu property (''%s'') to bool! Assuming false!', [tokenValue]));
                                  GameStatus.IsActiveMenu := false;
                                end;
                           end;
                         'can_hear_music':
                           begin
                             if TryStrToInt(tokenValue, i) then
                                GameStatus.CanHearMusic := (i <> 0)
                             else
                                begin
                                  Log('READ DATA', Format('Cannot convert CanHearMusic property (''%s'') to bool! Assuming false!', [tokenValue]));
                                  GameStatus.CanHearMusic := false;
                                end;
                           end;
                         'current_station_index':
                           begin
                             if TryStrToInt(tokenValue, i) then
                                GameStatus.CurrentStationIndex := i
                             else
                                begin
                                  Log('READ DATA', Format('Cannot convert CurrentStationIndex property (''%s'') to int! Assuming -1 (off)!', [tokenValue]));
                                  GameStatus.CurrentStationIndex := -1;
                                end;
                           end;
                         'faction_station':
                           begin
                             tok3 := Pos(' ', tokenValue);
                             if (tok3 < 0) then
                                tok3 := Pos(#9, tokenValue);
                             if (tok3 > 0) then
                                begin
                                  tokenName2 := Trim(LeftStr(tokenValue, tok3 - 1));
                                  tokenValue2 := Trim(RightStr(tokenValue, Length(tokenValue) - tok3));
                                  if TryStrToFloat(tokenValue2, f, X4OrsFormatSettings) then
                                     begin
                                       SetLength(ClosestStationData, Length(ClosestStationData) + 1);
                                       ClosestStationData[High(ClosestStationData)].FactionName := tokenName2;
                                       ClosestStationData[High(ClosestStationData)].DistanceKm := f / 1000.0; // To get the distance in km
                                     end
                                  else
                                     Log('READ DATA', Format('Cannot convert faction station distance definition value (''%s'') to float for faction ''%s''!', [tokenValue2, tokenName2]));

                                end
                             else
                                Log('READ DATA', Format('Cannot process invalid faction station distance definition (''%s'')!', [tokenValue]));
                           end;
                         else
                           Log('READ DATA', Format('Unknown gameplay property ''%s''!', [tokenName]));
                   end;

                   // Finished working with data
                   if (tok1 <= 0) then
                      PChar(MemoryBuffer)^ := #0;
                 end;
               'replay_mp3':
                 begin
                   Manager.ReplayCurrTrack;

                   // Finished working with data
                   PChar(MemoryBuffer)^ := #0;
                 end;
               'skip_mp3':
                 begin
                   Manager.SkipNextTrack;

                   // Finished working with data
                   PChar(MemoryBuffer)^ := #0;
                 end;
               'reload':
                 begin
                   // Finished working with data
                   PChar(MemoryBuffer)^ := #0;

                   // Signal that we must reload the application
                   Result := 2; // Reload signal
                 end;
               'request':
                 begin
                   // Construct answer
                   answer := '';
                   rsnames := Manager.GetNameList;
                   for i := 0 to High(rsnames) do
                       answer := answer + Format(#10'radio_station: %s', [rsnames[i]]);
                   for i := Low(KeyBindings) to High(KeyBindings) do
                       answer := answer + Format(#10'key_binding: %d %d', [i, KeyBindings[i].Key]);
                   answer := answer + Format(#10'latency: %d', [ProgramSettings.Latency]);

                   // Send data
                   SetLength(rsnames, 0);
                   SendData('programdata', Trim(answer), MemoryBuffer);
                 end;
               'programdata':
                 ; // Skip - the script didn't process the data yet!
               else
                 begin
                   Log('READ DATA', Format('Nonexistent EXE function ''%s''!', [exefunction]));

                   // Finished working with data
                   PChar(MemoryBuffer)^ := #0;
                 end;
         end;
       until (tok1 <= 0);
     end;
end;


// ********************************
// INIT, FINAL, RUN
// ********************************

procedure InitProgram;
var
  i, j, tok, slotCount: integer;
  slotOwners: TStringArray;
  loudFactor, dampFactor: double;
  slotFileName, slotOwnerList, slotOwner: string;
  radio: TRadioStation;
  mp3List: TStrings;
begin
  // Program initialization
  ZeroMemory(@GameStatus, sizeof(GameStatus));
  Manager := TRadioStationManager.Create;
  SetLength(ClosestStationData, 0);
  Settings := TIniFile.Create('settings.ini');

  // Global settings
  ProgramSettings.Latency := min(5000, max(10, ReadIntSetting(Settings, 'Global.Latency', 1000)));
  ProgramSettings.RandomizeTracks := (ReadIntSetting(Settings, 'Global.RandomizeTracks', 0) <> 0);
  ProgramSettings.NoOnlineStreams := (ReadIntSetting(Settings, 'Global.NoOnlineStreams', 0) <> 0);
  ProgramSettings.LinearVolume := (ReadIntSetting(Settings, 'Global.UseLinearVolume', 0) <> 0);
  ProgramSettings.MasterLoudness := min(1.0, max(0.0, ReadFloatSetting(Settings, 'Global.LoudnessFactor', 1.0)));

  // Key bindings
  for i := Low(KeyBindings) to High(KeyBindings) do
      KeyBindings[i].Key := ReadIntSetting(Settings, KeyBindings[i].IniSettingName, 0);

  // Radio stations
  for i := 1 to max(0, ReadIntSetting(Settings, 'Global.NumberOfStations', 0)) do
      begin
        radio := TRadioStation.Create;
        slotCount := ReadIntSetting(Settings, Format('Radio_%d.SlotCount', [i]), 0);
        for j := 1 to max(1, slotCount) do
            begin
              if (slotCount > 0) then
                 slotFileName := ReadStringSetting(Settings, Format('Radio_%d.SlotFileName_%d', [i, j]), '') // New-style
              else
                 slotFileName := ReadStringSetting(Settings, Format('Radio_%d.FileName', [i]), ''); // Old-style
              if (slotFileName = '') or (not IsNetFile(slotFileName)) and (not FileExists(slotFileName)) then
                 Log('INIT', Format('Radio station file ''%s'' does not exist!', [slotFileName]))
              else if IsNetFile(slotFileName) and ProgramSettings.NoOnlineStreams then
                 Log('INIT', Format('Ignoring online stream ''%s''...', [slotFileName]))
              else
                 begin
                   // Multi-owner system
                   SetLength(slotOwners, 0);
                   if (slotCount > 0) then
                      slotOwnerList := ReadStringSetting(Settings, Format('Radio_%d.SlotOwner_%d', [i, j]), '') // New-style
                   else
                      slotOwnerList := ReadStringSetting(Settings, Format('Radio_%d.Owner', [i]), ''); // Old-style
                   repeat
                      tok := Pos(',', slotOwnerList);
                      if (tok <= 0) then
                         slotOwner := Trim(slotOwnerList)
                      else
                         begin
                           slotOwner := Trim(LeftStr(slotOwnerList, tok - 1));
                           slotOwnerList := Trim(RightStr(slotOwnerList, Length(slotOwnerList) - tok));
                         end;
                      if (slotOwner <> '') then
                         begin
                           SetLength(slotOwners, Length(slotOwners) + 1);
                           slotOwners[High(slotOwners)] := slotOwner;
                         end;
                   until (tok <= 0);
                   if (slotCount > 0) then
                      begin
                        // New-style
                        loudFactor := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.SlotLoudnessFactor_%d', [i, j]), 0.0)));
                        dampFactor := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.SlotDampeningFactor_%d', [i, j]), 0.0)));
                        radio.AddRadioSlot(slotOwners, slotFileName, loudFactor, dampFactor);
                      end
                   else
                      begin
                        // Old-stlye
                        dampFactor := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.DampeningFactor', [i]), 0.0)));
                        radio.AddRadioSlot(slotOwners, slotFileName, 1.0, dampFactor);
                      end;
                   SetLength(slotOwners, 0);
                 end;
            end;
        if radio.IsValid then
           begin
             if (slotCount > 0) then
                radio.MasterVolume := ReadFloatSetting(Settings, Format('Radio_%d.MasterLoudnessFactor', [i]), 0.0) // New-style
             else
                radio.MasterVolume := ReadFloatSetting(Settings, Format('Radio_%d.LoudnessFactor', [i]), 0.0);  // Old-style
             radio.RadioStationName := ReadStringSetting(Settings, Format('Radio_%d.RadioText', [i]), '?Unnamed Station?');
             Manager.AddRadioStation(radio);
           end
        else
           begin
             radio.Free;
             Log('INIT', Format('Radio station %d failed to load!', [i]));
           end;
      end;

  // MP3 player radio station
  if (ReadIntSetting(Settings, 'Radio_MP3.Enabled', 0) <> 0) then
     begin
       mp3List := TStringList.Create;
       GetMP3Data(mp3List);
       if ProgramSettings.RandomizeTracks then
          ShuffleList(mp3List);
       if (mp3List.Count > 0) then
          begin
            radio := TRadioStation.Create(mp3List);
            if radio.IsValid then
               begin
                 if not NoLog then
                    radio.WriteReport('MP3Report.log');
                 radio.MasterVolume := min(1.0, max(0.0, ReadFloatSetting(Settings, 'Radio_MP3.LoudnessFactor', 0.0)));
                 radio.RadioStationName := ReadStringSetting(Settings, 'Radio_MP3.RadioText', '?Unnamed MP3 Station?');
                 Manager.AddRadioStation(radio);
               end
            else
              begin
                radio.Free;
                Log('INIT', 'Failed to load the MP3 Player radio station!');
              end;
          end;
       mp3List.Clear;
       mp3List.Free;
     end;
end;

procedure FiniProgram;
begin
  Manager.Free;
  SetLength(ClosestStationData, 0);
  Settings.Free;
end;

function RunProgram: boolean;
var
  lasttick: int64;
begin
  Result := false; // Result - FALSE: Must exit program after function return
  lasttick := GetTickCount64;

  // Initialize radio stations
  Manager.Process(-1, 0.0, nil, false);
  Manager.Status := rsPlaying;
  if ProgramSettings.RandomizeTracks then
     Manager.SetRandomPos(0.775);
  Manager.Status := rsPaused;

  // Event loop
  while IsGameRunning do
        begin
          MemoryBuffer := MapViewOfFile(SharedMemFile, FILE_MAP_ALL_ACCESS, 0, 0, SharedMemSize);
          try
            case ProcessGameData of
                  1:
                    begin
                      lasttick := GetTickCount64;
                      if GameStatus.IsActiveMenu then
                         begin
                           if GameStatus.CanHearMusic then
                              Manager.Process(GameStatus.CurrentStationIndex, ProgramSettings.MasterLoudness * GameStatus.MusicVolume, @ClosestStationData, ProgramSettings.LinearVolume)
                           else
                              Manager.Process(-1, 0.0, nil, false);
                           if (Manager.Status = rsPaused) then
                              Manager.Status := rsPlaying;
                         end
                      else if (Manager.Status <> rsPaused) then
                         Manager.Status := rsPaused;
                    end;
                  2:
                    begin
                      Log('MAIN', 'Reloading application...');
                      exit(true); // Result - TRUE: Must reload program after function return
                    end;
                  else
                    if (Manager.Status <> rsPaused) and ((GetTickCount64 - lasttick) > ProgramSettings.Latency) then
                       Manager.Status := rsPaused;
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
  i: integer;
  mustRunProgram: boolean;
  ProgramMutexHandle: HANDLE;

begin
  // ********************************
  // Application initialization
  // ********************************
  // Set working directory to real current directory (files must be accessible)
  GetModuleFileName(GetModuleHandle(nil), argv[0], 32767);
  SetCurrentDir(ExtractFilePath(ParamStr(0)));

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

