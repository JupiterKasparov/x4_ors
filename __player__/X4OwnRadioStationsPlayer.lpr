program X4OwnRadioStationsPlayer;

{$APPTYPE GUI}
{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

uses
    Windows, SysUtils, Classes, ctypes,
    Math, IniFiles, strutils,
    u_logger, u_song, u_radio, u_utils;

const
  // Application instance
  ProgramMutexName: string = 'jupiter_x4_ors__program_instance';
  ProgramPopupWindowName: string = 'X4: Foundations - Own Radio Stations - Playback Controller Application';

  // Shared memory
  SharedMemName: string = 'jupiter_x4_ors_memory__main_shared_mem';
  SharedMemSize = 262144;

  // Re-bindable key handling
  KeyBindingCount = 7;
  KeyBindingNames: array [1..KeyBindingCount] of string = ('Keys.Modifier_1', 'Keys.Modifier_2', 'Keys.Func_PrevStation', 'Keys.Func_NextStation', 'Keys.Func_ReplayThisMP3', 'Keys.Func_SkipThisMP3', 'Keys.Func_ReloadApp');

type
  TProgramSettings = record
    Latency: integer;
    RandomizeTracks: boolean;
    NoOnlineStreams: boolean;
    LinearVolume: boolean;
    MasterLoudness: double;
    KeyBindings: array [1..KeyBindingCount] of integer;
  end;

  TGameStatus = record
    CurrentStationIndex: integer;
    MusicVolume: double;   // Game setting
    IsActiveMenu: boolean; // False if the Pause Menu is active
    IsPiloting: boolean;   // True if piloting a spaceship
    IsAlive: boolean;      // False if Game Over screen is shown
  end;

  TKeyBindChangeStruct = array of record
    KeyIndex: integer;
    KeyID: integer;
  end;

var
  ProgramData: TProgramSettings;
  RadioStations: TRadioStationList;
  GameStatus: TGameStatus;
  ClosestStationData: TFactionDistanceDataArray;
  KeyBindingChange: TKeyBindChangeStruct;
  Settings: TIniFile;

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

procedure SendProgramData(mem: Pointer);
var
  data: string;
  i: integer;
begin
  // Init
  data := 'programdata'#10;

  // Radio station names
  for i := 0 to RadioStations.Count - 1 do
      data := data + Format('radio_station: %s'#10, [RadioStations[i].RadioStationName]);

  // Key bindings
  for i := 1 to High(ProgramData.KeyBindings) do
      data := data + Format('key_binding: %d %d'#10, [i, ProgramData.KeyBindings[i]]);

  // Latency
  data := data + Format('latency: %d'#10, [ProgramData.Latency]);

  // Send trimmed data to script
  data := Trim(data);
  ZeroMemory(mem, SharedMemSize);
  CopyMemory(mem, PChar(data), Length(data));
end;

function GetGameData(mem: Pointer; var status: TGameStatus; var distancedata: TFactionDistanceDataArray; var keybindchange: TKeyBindChangeStruct): integer;
var
  datastr, datatype, token, tokenName, tokenValue, tokenName2, tokenValue2: string;
  tok1, tok2, tok3, i, j: integer;
  f: double;
begin
  Result := 0; // 0 - Do nothing
  datastr := Trim(strpas(PChar(mem)));
  if (datastr <> '') then
     begin
        // Must change all 'foreign' linebreaks to linefeeds (separator)
        datastr := ReplaceStr(datastr, #13#10, #10);
        datastr := ReplaceStr(datastr, #13, #10);

        // EXE function ID
        tok1 := Pos(#10, datastr);
        if (tok1 > 0) then
           datatype := Trim(LeftStr(datastr, tok1 - 1))
        else
           datatype := Trim(datastr);
        datastr := Trim(RightStr(datastr, Length(datastr) - tok1));
        case LowerCase(datatype) of
              'gamedata':
                begin
                  // 1 - Must update stored game data
                  Result := 1;
                  SetLength(ClosestStationData, 0);
                  ZeroMemory(@GameStatus, sizeof(GameStatus));

                  // Line-by line parsing, on the fly
                  repeat
                    tok1 := Pos(#10, datastr);
                    if (tok1 > 0) then
                       begin
                          token := Trim(LeftStr(datastr, tok1 - 1));
                          datastr := Trim(RightStr(datastr, Length(datastr) - tok1));
                       end
                    else
                       token := Trim(datastr);
                    if (token <> '') then
                       begin
                          // Data token format - name:value
                          tok2 := Pos(':', token);
                          if (tok2 > 0) then
                             begin
                                tokenName := Trim(LeftStr(token, tok2 - 1));
                                tokenValue := Trim(RightStr(token, Length(token) - tok2));
                             end
                          else
                             begin
                               tokenName := Trim(token);
                               tokenValue := '';
                             end;

                          // Process game data tokens
                          case LowerCase(tokenName) of
                                'music_volume':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       status.MusicVolume := min(1.0, max(0.0, i / 100.0))
                                    else
                                       begin
                                         Log(Format('[READ DATA]: Cannot convert MusicVolume property (''%s'') to int! Assuming zero!', [tokenValue]));
                                         status.MusicVolume := 0.0;
                                       end;
                                  end;
                                'is_active_menu':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       status.IsActiveMenu := (i <> 0)
                                    else
                                       begin
                                         Log(Format('[READ DATA]: Cannot convert IsActiveMenu property (''%s'') to bool! Assuming false!', [tokenValue]));
                                         status.IsActiveMenu := false;
                                       end;
                                  end;
                                'is_piloting':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       status.IsPiloting := (i <> 0)
                                    else
                                       begin
                                         Log(Format('[READ DATA]: Cannot convert IsPiloting property (''%s'') to bool! Assuming false!', [tokenValue]));
                                         status.IsPiloting := false;
                                       end;
                                  end;
                                'is_alive':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       status.IsAlive := (i <> 0)
                                    else
                                       begin
                                         Log(Format('[READ DATA]: Cannot convert IsAlive property (''%s'') to bool! Assuming false!', [tokenValue]));
                                         status.IsAlive := false;
                                       end;
                                  end;
                                'current_station_index':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       status.CurrentStationIndex := i
                                    else
                                       begin
                                         Log(Format('[READ DATA]: Cannot convert CurrentStationIndex property (''%s'') to int! Assuming -1 (off)!', [tokenValue]));
                                         status.CurrentStationIndex := -1;
                                       end;
                                  end;
                                'faction_station':
                                  begin
                                    // Faction station distance data token format - factionname distancevalue
                                    tok3 := Pos(' ', tokenValue);
                                    if (tok3 < 0) then
                                       tok3 := Pos(#9, tokenValue);
                                    if (tok3 > 0) then
                                       begin
                                         tokenName2 := Trim(LeftStr(tokenValue, tok3 - 1));
                                         tokenValue2 := Trim(RightStr(tokenValue, Length(tokenValue) - tok3));
                                         if TryStrToFloat(tokenValue2, f, X4OrsFormatSettings) then
                                            begin
                                              SetLength(distancedata, Length(distancedata) + 1);
                                              distancedata[High(distancedata)].FactionName := tokenName2;
                                              distancedata[High(distancedata)].DistanceKm := f / 1000.0; // To get the distance in km
                                            end
                                         else
                                            Log(Format('[READ DATA]: Cannot convert faction station distance definition value ''%s'' to float for faction ''%s''!', [tokenValue2, tokenName2]));
                                       end
                                    else
                                       Log(Format('[READ DATA]: Cannot process faction station distance definition ''%s'', because it is invalid!', [tokenValue]));
                                  end;
                                else
                                  Log(Format('[READ DATA]: Ignoring unknown gameplay property ''%s''!', [tokenName]));
                          end;
                       end;
                  until (tok1 <= 0);

                  // Cleanup data
                  ZeroMemory(mem, SharedMemSize);
                end;
              'replay_mp3':
                begin
                  // 2 - Must jump to the beginning of the currently playing MP3
                  Result := 2;
                  ZeroMemory(mem, SharedMemSize);
                end;
              'skip_mp3':
                begin
                  // 3 - Must skip to the next MP3
                  Result := 3;
                  ZeroMemory(mem, SharedMemSize);
                end;
              'reload':
                begin
                  // 4 - Must reload the application
                  Result := 4;
                  ZeroMemory(mem, SharedMemSize);
                end;
              'set_key':
                begin
                  // 5 - Must store a key binding, that's been changed
                  Result := 5;

                  // Line-by line parsing, on the fly
                  SetLength(keybindchange, 0);
                  repeat
                    tok1 := Pos(#10, datastr);
                    if (tok1 > 0) then
                       begin
                          token := Trim(LeftStr(datastr, tok1 - 1));
                          datastr := Trim(RightStr(datastr, Length(datastr) - tok1));
                       end
                    else
                       token := Trim(datastr);
                    if (token <> '') then
                       begin
                         // Data token format - name:value
                         tok2 := Pos(':', token);
                          if (tok2 > 0) then
                             begin
                                tokenName := Trim(LeftStr(token, tok2 - 1));
                                tokenValue := Trim(RightStr(token, Length(token) - tok2));
                                if TryStrToInt(tokenName, i) and TryStrToInt(tokenValue, j) then
                                   begin
                                    SetLength(keybindchange, Length(keybindchange) + 1);
                                    keybindchange[High(keybindchange)].KeyIndex := i;
                                    keybindchange[High(keybindchange)].KeyID := j;
                                   end
                                else
                                   Log(Format('[READ DATA]: Cannot convert either the Key Binding Index (''%s'') or the Key Binding Value (''%s'') to int!', [tokenName, tokenValue]));
                             end
                          else
                             Log(Format('[READ DATA]: Cannot process key binding ''%s'', because it is invalid!', [token]));
                       end;
                  until (tok1 <= 0);

                  // Cleanup data
                  ZeroMemory(mem, SharedMemSize);
                end;
              'request':
                begin
                  // 6 - Must send data to LUA script
                  Result := 6;
                  ZeroMemory(mem, SharedMemSize);
                end;
              'programdata':
                ; // Skip - the LUA script didn't process the data yet!
              else
                begin
                  // Invalid data structure
                  Log(Format('[READ DATA]: Unknown data structure ''%s''!', [datatype]));
                  ZeroMemory(mem, SharedMemSize);
                end;
        end;
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
  slotFileName, slotOwnerToken, slotOwner: string;
  radio: TRadioStation;
  mp3List: TStrings;
begin
  // Program initialization
  RadioStations := TRadioStationList.Create;
  SetLength(ClosestStationData, 0);
  SetLength(KeyBindingChange, 0);
  Settings := TIniFile.Create('settings.ini');

  // Load settings
  ProgramData.Latency := min(5000, max(10, ReadIntSetting(Settings, 'Global.Latency', 1000)));
  ProgramData.RandomizeTracks := (ReadIntSetting(Settings, 'Global.RandomizeTracks', 0) <> 0);
  ProgramData.NoOnlineStreams := (ReadIntSetting(Settings, 'Global.NoOnlineStreams', 0) <> 0);
  ProgramData.LinearVolume := (ReadIntSetting(Settings, 'Global.UseLinearVolume', 0) <> 0);
  ProgramData.MasterLoudness := min(1.0, max(0.0, ReadFloatSetting(Settings, 'Global.LoudnessFactor', 1.0)));

  // Key bindings
  for i := 1 to KeyBindingCount do
      ProgramData.KeyBindings[i] := ReadIntSetting(Settings, KeyBindingNames[i], 0);

  // Normal radio stations
  for i := 0 to max(0, ReadIntSetting(Settings, 'Global.NumberOfStations', 0)) - 1 do
      begin
        radio := TRadioStation.Create;
        slotCount := ReadIntSetting(Settings, Format('Radio_%d.SlotCount', [i + 1]), 0);
        for j := 1 to max(1, slotCount) do
            begin
              if (slotCount > 0) then
                 slotFileName := ReadStringSetting(Settings, Format('Radio_%d.SlotFileName_%d', [i + 1, j]), '') // New-style
              else
                 slotFileName := ReadStringSetting(Settings, Format('Radio_%d.FileName', [i + 1]), ''); // Old-style
              if (slotFileName = '') or (not IsNetFile(slotFileName)) and (not FileExists(slotFileName)) then
                 Log(Format('[INIT]: Radio station file ''%s'' does not exist!', [slotFileName]))
              else if IsNetFile(slotFileName) and ProgramData.NoOnlineStreams then
                 Log(Format('[INIT]: The application is set to ignore online streams. Ignoring ''%s''...', [slotFileName]))
              else
                 begin
                   // Multi-owner system
                   SetLength(slotOwners, 0);
                   if (slotCount > 0) then
                      slotOwnerToken := ReadStringSetting(Settings, Format('Radio_%d.SlotOwner_%d', [i + 1, j]), '') // New-style
                   else
                      slotOwnerToken := ReadStringSetting(Settings, Format('Radio_%d.Owner', [i + 1]), ''); // Old-style
                   repeat
                     tok := Pos(',', slotOwnerToken);
                     if (tok <= 0) then
                        slotOwner := Trim(slotOwnerToken)
                     else
                        begin
                          slotOwner := Trim(LeftStr(slotOwnerToken, tok - 1));
                          slotOwnerToken := Trim(RightStr(slotOwnerToken, Length(slotOwnerToken) - tok));
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
                          loudFactor := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.SlotLoudnessFactor_%d', [i + 1, j]), 0.0)));
                          dampFactor := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.SlotDampeningFactor_%d', [i + 1, j]), 0.0)));
                          radio.AddRadioSlot(slotOwners, slotFileName, loudFactor, dampFactor);
                        end
                     else
                        begin
                          // Old-stlye
                          dampFactor := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.DampeningFactor', [i + 1]), 0.0)));
                          radio.AddRadioSlot(slotOwners, slotFileName, 1.0, dampFactor);
                        end;
                   SetLength(slotOwners, 0);
                 end;
            end;
        if (slotCount > 0) then
           radio.Volume := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.MasterLoudnessFactor', [i + 1]), 0.0))) // New-style
        else
           radio.Volume := min(1.0, max(0.0, ReadFloatSetting(Settings, Format('Radio_%d.LoudnessFactor', [i + 1]), 0.0)));  // Old-style
        if radio.IsValid then
           begin
             radio.RadioStationName := ReadStringSetting(Settings, Format('Radio_%d.RadioText', [i + 1]), '?Unnamed Station?');
             RadioStations.Add(radio);
           end
        else
           radio.Free;
      end;
  // MP3 station data
  if (ReadIntSetting(Settings, 'Radio_MP3.Enabled', 0) <> 0) then
     begin
       mp3List := TStringList.Create;
       GetMP3Data(mp3List);
       if (mp3List.Count > 0) then
          begin
            radio := TRadioStation.Create(mp3List);
            if radio.IsValid then
               begin
                 if not NoLog then
                    radio.WriteReport('MP3Report.log');
                 radio.Volume := min(1.0, max(0.0, ReadFloatSetting(Settings, 'Radio_MP3.LoudnessFactor', 0.0)));
                 radio.RadioStationName := ReadStringSetting(Settings, 'Radio_MP3.RadioText', '?Unnamed MP3 Station?');
                 RadioStations.Add(radio);
               end
            else
              radio.Free;
          end;
       mp3List.Clear;
       mp3List.Free;
     end;
end;

procedure FiniProgram;
var
  i: integer;
begin
  for i := 0 to RadioStations.Count - 1 do
      RadioStations[i].Free;
  RadioStations.Free;
  SetLength(ClosestStationData, 0);
  SetLength(KeyBindingChange, 0);
  Settings.Free;
end;

function RunProgram(sharedMem: HANDLE): boolean;
var
  i: integer;
  paused: boolean;
  lasttick: int64;
  mem: Pointer;
begin
  Result := false; // Result - FALSE: Must exit program after function return
  paused := true;
  lasttick := GetTickCount64;

  // Initialize radio stations
  for i := 0 to RadioStations.Count - 1 do
      begin
        RadioStations[i].Update(nil, 0.0, false);
        if ProgramData.RandomizeTracks then
           RadioStations[i].SetRandomPos;
        RadioStations[i].Status := rsPaused;
      end;

  // Main loop
  while IsGameRunning do
        begin
          mem := MapViewOfFile(sharedMem, FILE_MAP_ALL_ACCESS, 0, 0, SharedMemSize);
          try
            case GetGameData(mem, GameStatus, ClosestStationData, KeyBindingChange) of
                  1:
                    begin
                      // Update
                      lasttick := GetTickCount64;
                      if GameStatus.IsActiveMenu and paused then
                         begin
                           paused := false;
                           for i := 0 to RadioStations.Count - 1 do
                               RadioStations[i].Status := rsPlaying;
                         end
                      else if (not GameStatus.IsActiveMenu) and (not paused) then
                         begin
                           paused := true;
                           for i := 0 to RadioStations.Count - 1 do
                               RadioStations[i].Status := rsPaused;
                         end;
                      for i := 0 to RadioStations.Count - 1 do
                          if (GameStatus.CurrentStationIndex = i) and GameStatus.IsAlive and GameStatus.IsPiloting then
                             RadioStations[i].Update(@ClosestStationData, ProgramData.MasterLoudness * GameStatus.MusicVolume, ProgramData.LinearVolume)
                          else
                             RadioStations[i].Update(nil, 0.0, false);
                    end;
                  2:
                    begin
                      // Replay current MP3
                      if (GameStatus.CurrentStationIndex >= 0) and (GameStatus.CurrentStationIndex < RadioStations.Count) and (RadioStations[GameStatus.CurrentStationIndex].IsMP3Station) then
                         RadioStations[GameStatus.CurrentStationIndex].ReplayCurrTrack;
                    end;
                  3:
                    begin
                      // Skip to next MP3
                      if (GameStatus.CurrentStationIndex >= 0) and (GameStatus.CurrentStationIndex < RadioStations.Count) and (RadioStations[GameStatus.CurrentStationIndex].IsMP3Station) then
                         RadioStations[GameStatus.CurrentStationIndex].SkipNextTrack;
                    end;
                  4:
                    begin
                      // Trigger app reload
                      Log('[MAIN]: The application is now going to reload...');
                      exit(true); // Result - TRUE: Must reload program after function return
                    end;
                  5:
                    begin
                      // Store Key Binding(s)
                      for i := 0 to High(KeyBindingChange) do
                          begin
                            if (KeyBindingChange[i].KeyIndex >= 1) and (KeyBindingChange[i].KeyIndex <= KeyBindingCount) then
                               begin
                                 ProgramData.KeyBindings[KeyBindingChange[i].KeyIndex] := KeyBindingChange[i].KeyID;
                                 WriteIntSetting(Settings, KeyBindingNames[KeyBindingChange[i].KeyIndex], KeyBindingChange[i].KeyID);
                               end
                            else
                               Log(Format('[MAIN]: Cannot store Key Binding %d, because it is out of range!', [KeyBindingChange[i].KeyIndex]));
                          end;
                      SetLength(KeyBindingChange, 0);
                    end;
                  6:
                    // Send data to LUA
                    SendProgramData(mem);
            end;
          finally
            UnmapViewOfFile(mem);
          end;

          // Pause radio stations, if no heartbeat signal for too long
          if (not paused) and ((GetTickCount64 - lasttick) > programdata.Latency) then
             begin
               paused := true;
               for i := 0 to RadioStations.Count - 1 do
                   RadioStations[i].Status := rsPaused;
             end;

          // Don't consume 100% CPU, we have to wait
          Sleep(ProgramData.Latency div 4);
        end;
end;

// ********************************
// MAIN
// ********************************

{$R *.res}

var
  i: integer;
  mustRunProgram: boolean;
  SharedMemHandle, ProgramMutexHandle: HANDLE;

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
     MessageBox(0, 'X4: Foundations is not running!', PChar(ProgramPopupWindowName), MB_OK + MB_ICONERROR)
  else
     begin
       ProgramMutexHandle := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), PChar(ProgramMutexName));
       if (ProgramMutexHandle = 0) then
          begin
            ProgramMutexHandle := CreateMutex(nil, BOOL(1), PChar(ProgramMutexName));
            try
              SharedMemHandle := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SharedMemSize, PChar(SharedMemName));
              if (SharedMemHandle <> 0) then
                 begin
                   try
                     while mustRunProgram do
                           try
                             InitProgram;
                             try
                               mustRunProgram := RunProgram(SharedMemHandle);
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
                     CloseHandle(SharedMemHandle);
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
          begin
            CloseHandle(ProgramMutexHandle);
            MessageBox(0, 'This application must have a single instance only!', PChar(ProgramPopupWindowName), MB_OK + MB_ICONERROR);
          end;
     end;
end.

