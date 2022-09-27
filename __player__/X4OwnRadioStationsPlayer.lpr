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
  mtxApplication: string = 'jupiter_x4_ors__program_instance';
  nameAppName: string = 'X4: Foundations - Own Radio Stations - Playback Controller Application';

  // Shared memory
  memSharedMem: string = 'jupiter_x4_ors_memory__main_shared_mem';
  datalen = 262144;

  // Re-bindable key handling
  keycount = 7;
  keynames: array [1..keycount] of string = ('Keys.Modifier_1', 'Keys.Modifier_2', 'Keys.Func_PrevStation', 'Keys.Func_NextStation', 'Keys.Func_ReplayThisMP3', 'Keys.Func_SkipThisMP3', 'Keys.Func_ReloadApp');

type
  TGameData = record
    {IG script status}
    GameStatus: record
      CurrentStationIndex: integer;
      MusicVolume: double; // Game setting
      IsActiveMenu: integer;  // So not the Pause-Menu
      IsDriving: integer;     // Is driving a spaceship?
      IsAlive: integer;       // False if Game Over screen is shown
    end;
    {Nearest stations by faction}
    NearestStations: array of record
      Owner: string;
      Distance: double;
    end;
  end;

  TRadioData = record
    RsName: string;
    Owners: array of string; // Owner faction (the radio station is emitted from the owner's stations)
    LoudnessFactor, DampeningFactor: double;
    Handler: TRadioStation;
  end;

  TRadioDataList = array of TRadioData;

  TProgramData = record
    MasterLoudness: double;
    MaxLatency: integer;
    RandomizeTracks: boolean;
    NoOnlineStreams: boolean;
    Keys: array [1..keycount] of integer;
  end;

var
  // Data storage
  gamedata: TGameData;
  programdata: TProgramData;
  stations: TRadioDataList;
  settings: TIniFile;

  // Working vars
  mapfile: HANDLE;
  mutex: HANDLE;

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

function Settings_ReadString(name, def: string): string;
var
  tok: integer;
  value: string;
begin
  tok := Pos('.', name);
  if (tok <= 0) then
     value := def;
  value := RightStr(name, Length(name) - tok);
  name := LeftStr(name, tok - 1);
  Result := settings.ReadString(name, value, def);
end;

function Settings_ReadInt(name: string; def: integer): integer;
var
  i: integer;
  s: string;
begin
  s := Settings_ReadString(name, '??');
  if TryStrToInt(s, i) then
     Result := i
  else
     Result := def;
end;

function Settings_ReadFloat(name: string; def: double): double;
var
  f: double;
  s: string;
begin
  s := Settings_ReadString(name, '??');
  if TryStrToFloat(s, f, settings.FormatSettings) then
     Result := f
  else
     Result := def;
end;

procedure Settings_WriteString(name, value: string);
var
  tok: integer;
  section, identifier: string;
begin
  tok := Pos('.', name);
  if (tok <= 0) then
     begin
      section := '';
      identifier := name;
     end
  else
     begin
       section := LeftStr(name, tok - 1);
       identifier := RightStr(name, Length(name) - tok);
     end;
  settings.WriteString(section, identifier, value);
end;

procedure Settings_WriteInt(name: string; value: integer);
begin
  Settings_WriteString(name, IntToStr(value));
end;

procedure Settings_WriteFloat(name: string; value: double);
begin
  Settings_WriteString(name, FloatToStr(value, settings.FormatSettings));
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

procedure ApplyCalculatedVolume(station: TRadioData);
var
  damp, d: double;
  i, j: integer;
begin
  if (Length(station.Owners) > 0) then
     begin
      damp := 0;
      for i := 0 to High(station.Owners) do
          for j := 0 to High(gamedata.NearestStations) do
              if (CompareText(station.Owners[i], gamedata.NearestStations[j].Owner) = 0)then
                 begin
                    // Multi-Owner check. The loudest loudness wins!
                    if (gamedata.NearestStations[j].Distance > 0.0) then
                       d := power(station.DampeningFactor, gamedata.NearestStations[j].Distance)
                    else
                       d := 1.0;
                    if (d > damp) then
                       damp := d;
                 end;
     end
  else
     damp := 1.0;
  station.Handler.SetVolume(damp * station.LoudnessFactor * programdata.MasterLoudness * gamedata.GameStatus.MusicVolume);
end;

procedure SendProgramData(mem: Pointer);
var
  data: string;
  i: integer;
begin
  // Init
  ZeroMemory(mem, datalen);
  data := 'programdata'#10;

  // Latency
  data := data + Format('latency: %d'#10, [programdata.MaxLatency]);

  // Radio station names
  for i := 0 to High(stations) do
      data := data + Format('radio_station: %s'#10, [stations[i].RsName]);

  // Key binding
  for i := 1 to keycount do
      data := data + Format('key_binding: %d %d'#10, [i, programdata.Keys[i]]);

  // Trim data, and send it to script
  data := Trim(data);
  CopyMemory(mem, PChar(data), Length(data));
end;

function ReceiveGameData: integer;
var
  data: Pointer;
  h, i, j, tok1, tok2, tok3, tok4: integer;
  f: cfloat;
  datastr, datatype, token, tokenName, tokenValue, token2, tokenName2, tokenValue2: string;
begin
  Result := 0; // Nothing to do afterwards

  // Read data from shared mem
  data := MapViewOfFile(mapfile, FILE_MAP_ALL_ACCESS, 0, 0, datalen);
  datastr := Trim(strpas(PChar(data)));

  // Parse the data structure, and read the data
  if (datastr <> '') then
     begin
        // The separator is #10 (linefeed); change all 'foreign' linebreaks to linefeeds
        datastr := ReplaceStr(datastr, #13#10, #10);
        datastr := ReplaceStr(datastr, #13, #10);

        // Get the data type (function identifier) - 1st line of incoming data
        tok1 := Pos(#10, datastr);
        if (tok1 > 0) then
           datatype := Trim(LeftStr(datastr, tok1 - 1))
        else
           datatype := Trim(datastr);
        // Chop off the function identifier, to get the actual data
        datastr := Trim(RightStr(datastr, Length(datastr) - tok1));

        // Execute the desired function
        case LowerCase(datatype) of
              'gamedata':
                begin
                  Result := 1; // This is a game data, program must refresh internal state after function return

                  // Zero out the internal game data structure
                  SetLength(gamedata.NearestStations, 0);
                  ZeroMemory(@gamedata, sizeof(gamedata));

                  // Tokenize the whole data string, and parse it on the fly. Each 'line' is a gameplay property, in a 'name:value' format
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

                          // Fill the gamedata structure by parsing properties
                          case LowerCase(tokenName) of
                                'music_volume':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       gamedata.GameStatus.MusicVolume := min(1.0, max(0.0, i / 100.0))
                                    else
                                       begin
                                        Log(Format('[READ DATA]: Music volume ''%s'' is an invalid integer! Assuming zero!', [tokenValue]));
                                        gamedata.GameStatus.MusicVolume := 0.0;
                                       end;
                                  end;
                                'is_active_menu':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       gamedata.GameStatus.IsActiveMenu := i
                                    else
                                       begin
                                        Log(Format('[READ DATA]: IsActiveMenu boolean ''%s'' is an invalid integer! Assuming zero (false)!', [tokenValue]));
                                        gamedata.GameStatus.IsActiveMenu := 0;
                                       end;
                                  end;
                                'is_driving':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       gamedata.GameStatus.IsDriving := i
                                    else
                                       begin
                                        Log(Format('[READ DATA]: IsDriving boolean ''%s'' is an invalid integer! Assuming zero (false)!', [tokenValue]));
                                        gamedata.GameStatus.IsDriving := 0;
                                       end;
                                  end;
                                'is_alive':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       gamedata.GameStatus.IsAlive := i
                                    else
                                       begin
                                        Log(Format('[READ DATA]: IsAlive boolean ''%s'' is an invalid integer! Assuming zero (false)!', [tokenValue]));
                                        gamedata.GameStatus.IsAlive := 0;
                                       end;
                                  end;
                                'current_station_index':
                                  begin
                                    if TryStrToInt(tokenValue, i) then
                                       gamedata.GameStatus.CurrentStationIndex := i
                                    else
                                       begin
                                        Log(Format('[READ DATA]: CurrentStationIndex ''%s'' is an invalid integer! Assuming -1 (off)!', [tokenValue]));
                                        gamedata.GameStatus.CurrentStationIndex := -1;
                                       end;
                                  end;
                                'faction_station':
                                  begin
                                    repeat
                                      tok3 := Pos(',', tokenValue);
                                      if (tok3 > 0) then
                                         begin
                                          token2 := Trim(LeftStr(tokenValue, tok3 - 1));
                                          tokenValue := Trim(RightStr(tokenValue, Length(tokenValue) - tok3));
                                         end
                                      else
                                         token2 := Trim(tokenValue);
                                      tok4 := Pos(' ', token2);
                                      if (tok4 < 0) then
                                         tok4 := Pos(#9, token2);
                                      if (tok4 > 0) then
                                         begin
                                          tokenName2 := Trim(LeftStr(token2, tok4 - 1));
                                          tokenValue2 := Trim(RightStr(token2, Length(token2) - tok4));
                                          if TryStrToFloat(tokenValue2, f, settings.FormatSettings) then
                                             begin
                                              SetLength(gamedata.NearestStations, Length(gamedata.NearestStations) + 1);
                                              h := High(gamedata.NearestStations);
                                              gamedata.NearestStations[h].Owner := tokenName2;
                                              gamedata.NearestStations[h].Distance := f / 1000.0; // To get the distance in km
                                              //
                                             end
                                          else
                                             Log(Format('[READ DATA]: Faction ''%s'' station distance ''%s'' is not a valid integer or float!', [tokenName2, tokenValue2]));
                                         end
                                      else
                                         Log(Format('[READ DATA]: Faction station distance definition ''%s'' is invalid!', [token2]));
                                    until (tok3 <= 0);
                                  end;
                                else
                                  Log(Format('[READ DATA]: Unknown gameplay property ''%s''!', [tokenName]));
                          end;
                       end;
                  until (tok1 <= 0);

                  // Zero out the working memory
                  ZeroMemory(data, datalen);
                end;
              'replay_mp3':
                begin
                  Result := 2; // Replay the currently played MP3 after funtion return
                  // Zero out the working memory
                  ZeroMemory(data, datalen);
                end;
              'skip_mp3':
                begin
                  Result := 3; // Skip to the next MP3 after function return
                  // Zero out the working memory
                  ZeroMemory(data, datalen);
                end;
              'reload':
                begin
                  Result := 4; // Program must fully reload after function return
                  // Zero out the working memory
                  ZeroMemory(data, datalen);
                end;
              'set_key':
                begin
                  Result := 5; // A key binding is changed

                  // Get the key index and new key value
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
                          if TryStrToInt(tokenName, i) and TryStrToInt(tokenValue, j) then
                             begin
                                if (i > 0) and (i <= keycount) then
                                   begin
                                      programdata.Keys[i] := j;
                                      Settings_WriteInt(keynames[i], j);
                                   end
                                else
                                   Log(Format('[READ DATA]: Can''t change key %d, index is out of range!!', [i]));
                             end
                          else
                             Log(Format('[READ DATA]: Invalid key change sequence ''%s''!', [token]));
                       end;
                  until (tok1 <= 0);
                  // Zero out the working memory
                  ZeroMemory(data, datalen);
                end;
              'request':
                begin
                  Result := 0; // The program must send data right now
                  SendProgramData(data);
                end;
              'programdata':
                begin
                  Result := 0; // The script didn't process the data. Nothing to do...
                end;
              else
                begin
                  Log(Format('[READ DATA]: Unknown data structure ''%s''!', [datatype]));
                  // Zero out the working memory
                  ZeroMemory(data, datalen);
                end;
        end;
     end;

  // Clean up
  UnmapViewOfFile(data);
  datastr := '';
end;

// ********************************
// INIT, FINAL, RUN
// ********************************

procedure InitProgram;
var
  i, numstations, tok: integer;
  filename, token, ow: string;
  radio: TRadioStation;
  mp3list: TStrings;
begin
  // Init stations
  SetLength(stations, 0);

  // Init game data
  SetLength(gamedata.NearestStations, 0);
  ZeroMemory(@gamedata, sizeof(gamedata));

  // Init settings
  settings := TIniFile.Create('settings.ini', [ifoFormatSettingsActive]);
  settings.FormatSettings.DecimalSeparator := '.';
  // Latency
  programdata.MaxLatency := min(5000, max(10, Settings_ReadInt('Global.Latency', 1000)));
  // Loudness
  programdata.MasterLoudness := min(1.0, max(0.0, Settings_ReadFloat('Global.LoudnessFactor', 1.0)));
  // Randomize tracks?
  programdata.RandomizeTracks := (Settings_ReadInt('Global.RandomizeTracks', 0) <> 0);
  // No online streams?
  programdata.NoOnlineStreams := (Settings_ReadInt('Global.NoOnlineStreams', 0) <> 0);;

  // Linearize volume?
  bLinearizeVolume := (Settings_ReadInt('Global.UseLinearVolume', 0) <> 0);

  // No of stations
  numstations := max(0, Settings_ReadInt('Global.NumberOfStations', 0));

  // Keys
  for i := 1 to keycount do
      programdata.Keys[i] := Settings_ReadInt(keynames[i], 0);

  // Load radio stations
  for i := 0 to numstations - 1 do
      begin
        filename := Settings_ReadString(Format('Radio_%d.FileName', [i + 1]), '');
        if (filename = '') then
           Log('[INIT]: Empty radio station file name!')
        else if (not IsNetFile(filename)) and (not FileExists(filename)) then
           Log(Format('[INIT]: Radio station file ''%s'' does not exist!', [filename]))
        else if IsNetFile(filename) and programdata.NoOnlineStreams then
           Log(Format('[INIT]: Application is set to ignore online streams, ignoring ''%s''!', [filename]))
        else
           begin
            radio := TRadioStation.Create(filename);
            // Only register valid stations
            if radio.Valid then
               begin
                SetLength(stations, Length(stations) + 1);
                with stations[High(stations)] do
                     begin
                       RsName := Settings_ReadString(Format('Radio_%d.RadioText', [i + 1]), '?Unnamed Station?');
                       SetLength(Owners, 0);
                       // Multi-Owner system!
                       token := Settings_ReadString(Format('Radio_%d.Owner', [i + 1]), '');
                       repeat
                         tok := Pos(',', token);
                         if (tok <= 0) then
                            ow := Trim(token)
                         else
                            begin
                                 ow := Trim(LeftStr(token, tok - 1));
                                 token := Trim(RightStr(token, Length(token) - tok));
                            end;
                         if (ow <> '') then
                            begin
                             SetLength(Owners, Length(Owners) + 1);
                             Owners[High(Owners)] := ow;
                            end;
                       until (tok <= 0);
                       // End Multi-Owner system
                       LoudnessFactor := min(1.0, max(0.0, Settings_ReadFloat(Format('Radio_%d.LoudnessFactor', [i + 1]), 0.0)));
                       DampeningFactor := min(1.0, max(0.0, Settings_ReadFloat(Format('Radio_%d.DampeningFactor', [i + 1]), 1.0)));
                       Handler := radio;
                     end;
               end
            else
               radio.Free;
            radio := nil;
           end;
      end;
  // MP3 station data
  if (Settings_ReadInt('Radio_MP3.Enabled', 0) <> 0) then
     begin
      mp3list := TStringList.Create;
      GetMP3Data(mp3list);
      if (mp3list.Count > 0) then
         begin
          radio := TRadioStation.Create(mp3list, true);
          if radio.Valid then
             begin
              if not bNoLog then
                 radio.WriteMP3Report('MP3Report.log');
              SetLength(stations, Length(stations) + 1);
              with stations[High(stations)] do
                   begin
                     RsName := Settings_ReadString('Radio_MP3.RadioText', '?Unnamed MP3 Station?');
                     SetLength(Owners, 0);
                     LoudnessFactor := min(1.0, max(0.0, Settings_ReadFloat('Radio_MP3.LoudnessFactor', 0.0)));
                     DampeningFactor := 1.0;
                     Handler := radio;
                   end;
             end
          else
             radio.Free;
          radio := nil;
         end;
      mp3list.Clear;
      mp3list.Free;
     end;
end;

procedure FiniProgram;
var
  i: integer;
begin
  for i := 0 to High(stations) do
      begin
        stations[i].Handler.Free;
        SetLength(stations[i].Owners, 0);
      end;
  SetLength(stations, 0);
  SetLength(gamedata.NearestStations, 0);
  settings.Free;
end;

procedure RunProgram;
var
  i, h: integer;
  inited: boolean = false;
  paused: boolean = false;
  lasttick: int64 = 0;
begin
  while IsGameRunning do
        begin
          // Pre-Init stations, if not yet initialized
          if not inited then
             begin
              inited := true;
              for i := 0 to High(stations) do
                  begin
                    stations[i].Handler.SetVolume(0.0);
                    if programdata.RandomizeTracks then
                       stations[i].Handler.RandomizePosition;
                  end;
             end;

          // Read the game data
          case ReceiveGameData of
                1:
                  begin
                    // Update heartbeat monitor
                    lasttick := GetTickCount64;

                    // Check for IsActiveMenu bool
                    if (gamedata.GameStatus.IsActiveMenu <> 0) and paused then
                       begin
                        paused := false;
                        for i := 0 to High(stations) do
                            stations[i].Handler.SetPaused(false);
                       end
                    else if (gamedata.GameStatus.IsActiveMenu = 0) and (not paused) then
                       begin
                        paused := true;
                        for i := 0 to High(stations) do
                            stations[i].Handler.SetPaused(true);
                       end;

                    // Update volume
                    for i := 0 to High(stations) do
                        if (gamedata.GameStatus.CurrentStationIndex = i) and (gamedata.GameStatus.IsAlive <> 0) and (gamedata.GameStatus.IsDriving <> 0) then
                           ApplyCalculatedVolume(stations[i])
                        else
                           stations[i].Handler.SetVolume(0.0);
                  end;
                2:
                  begin
                    h := High(stations);
                    if (gamedata.GameStatus.CurrentStationIndex = h) and stations[i].Handler.IsMP3Station then
                       stations[h].Handler.Replay;
                  end;
                3:
                  begin
                    h := High(stations);
                    if (gamedata.GameStatus.CurrentStationIndex = h) and stations[i].Handler.IsMP3Station then
                       stations[h].Handler.SkipNextTrack;
                  end;
                4:
                  begin
                    Log('[RELOAD]: The program received the message to fully reload - reloading...');
                    i := programdata.MaxLatency;
                    inited := false;
                    paused := false;
                    FiniProgram;
                    Sleep(i div 4);
                    InitProgram;
                    Log('[RELOAD]: Successfully reloaded!');
                    continue; // Skip to next loop
                  end;
          end;

          // Pause radio stations, if no heartbeat signal for too long
          if (not paused) and ((GetTickCount64 - lasttick) > programdata.MaxLatency) then
             begin
              paused := true;
              for i := 0 to High(stations) do
                  stations[i].Handler.SetPaused(true);
             end;

          // Progress station handlers
          for i := 0 to High(stations) do
              stations[i].Handler.DoProgress;

          // Don't consume 100% CPU, we have to wait
          Sleep(programdata.MaxLatency div 4);
        end;
end;

// ********************************
// MAIN
// ********************************

{$R *.res}

var
  i: integer;

begin
  // ********************************
  // Application initialization
  // ********************************
  // Set working directory to real current directory (files must be accessible)
  GetModuleFileName(GetModuleHandle(nil), argv[0], 32767);
  SetCurrentDir(ExtractFilePath(ParamStr(0)));

  // If the priority is too low, set it to Above Normal (so music won't freeze)
  if (GetPriorityClass(GetCurrentProcess) <> $8000) and (GetPriorityClass(GetCurrentProcess) <> $100) then
     SetPriorityClass(GetCurrentProcess, $8000);

  // RNG init
  randomize;

  // CmdLine param get
  for i := 1 to ParamCount do
      if (LowerCase(ParamStr(i)) = '-nolog') then
         bNoLog := true;

  // ********************************
  // Application main part
  // ********************************
  mutex := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), PChar(mtxApplication));
  if (mutex = 0) then
     begin
       mutex := CreateMutex(nil, BOOL(0), PChar(mtxApplication));
       if IsGameRunning then
          begin
            mapfile := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, datalen, PChar(memSharedMem));
            if (mapfile <> 0) then
               begin
                try
                  InitProgram;
                  try
                     RunProgram;
                  except
                     LogError(ExceptObject, ExceptAddr);
                     LogError('Fatal error in main loop!');
                     ExitCode := 2;
                  end;
                  try
                      FiniProgram;
                  except
                     LogError(ExceptObject, ExceptAddr);
                     LogError('Fatal error in finalization!');
                     ExitCode := 3;
                  end;
                 except
                   LogError(ExceptObject, ExceptAddr);
                   LogError('Fatal error in initialization!');
                   ExitCode := 1;
                 end;
                 CloseHandle(mapfile);
               end
            else
               begin
                 LogError(Format('Failed to setup shared memory, error code: %d!', [GetLastError]));
                 ExitCode := 1;
               end;
           end
        else
           MessageBox(0, 'X4: Foundations is not running!', PChar(nameAppName), MB_OK + MB_ICONERROR);
        ReleaseMutex(mutex);
     end
  else
     MessageBox(0, 'This application must have a single instance only!', PChar(nameAppName), MB_OK + MB_ICONERROR);
end.

