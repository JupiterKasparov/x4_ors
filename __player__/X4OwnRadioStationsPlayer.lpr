program X4OwnRadioStationsPlayer;

{$APPTYPE GUI}
{$MODE OBJFPC}
{$H+}
{$PACKRECORDS C}

uses
    Windows, SysUtils, Classes, ctypes,
    Math, IniFiles, strutils,
    u_logger, u_radio, u_utils;

const
  // Application instance
  mtxApplication: string = 'jupiter_x4_ors__program_instance';
  nameAppName: string = 'X4: Foundations - Own Radio Stations - Playback Controller Application';

  // Shared memory
  memSharedMem: string = 'jupiter_x4_ors_memory__main_shared_mem';
  datalen = 262144;

  // Control tokens
  rqGameData: string = 'gamedata';
  rqRequestData: string = 'request';
  rqProgramData: string = 'programdata';
  rqReplayTrack: string = 'replay_mp3';
  rqNextTrack: string = 'skip_next_mp3';

type
  TGameData = record
    CurrentControlToken: integer;
    {IG script status}
    GameStatus: record
      CurrentStationIndex: cint;
      MusicVolume: cfloat; // Game setting
      IsActiveMenu: cint;  // So not the Pause-Menu
      IsDriving: cint;     // Is driving a spaceship?
      IsAlive: cint;       // False if Game Over screen is shown
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

{Returns if X4 is currently running}
function IsGameRunning: boolean;
var
  gamemutex: HANDLE;
begin
  gamemutex := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), 'EGOSOFT_X4_INSTANCE');
  Result := gamemutex <> 0;
  if Result then
     CloseHandle(gamemutex);
end;

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
  ZeroMemory(mem, datalen);
  data := rqProgramData;
  data := data + Format('latency: %d', [programdata.MaxLatency]);
  if (Length(stations) > 0) then
     data := data + ',';
  for i := 0 to High(stations) do
      begin
        data := data + Format('radio_name: %s', [stations[i].RsName]);
        if (i < High(stations)) then
           data := data + ',';
      end;
  CopyMemory(mem, PChar(data), Length(data));
end;

function ReadGameData: boolean;
var
  data: Pointer;
  h, i, tok1, tok2, tok3: integer;
  f: cfloat;
  datastr, currentToken, tokenName, tokenValue: string;
begin
  // Default: has no data
  Result := false;

  // Read data from shared mem
  data := MapViewOfFile(mapfile, FILE_MAP_ALL_ACCESS, 0, 0, datalen);
  datastr := Trim(strpas(PChar(data)));

  // Look through the data, if we have anything
  if (datastr <> '') then
     begin
      // Token: game data (EXE must process this data)
      if AnsiStartsText(rqGameData, datastr) then
         begin
          // Is heartbeat signal? Yes!
          Result := true;

          // Zero out the Game Data structure
          SetLength(gamedata.NearestStations, 0);
          ZeroMemory(@gamedata, sizeof(gamedata));
          gamedata.CurrentControlToken := 1; // Ct: Game Data (structure updated!)

          // Cut off datatype ID
          datastr := RightStr(datastr, Length(datastr) - Length(rqGameData));

          // Tokenize whole string (get next token)
          repeat
            tok1 := Pos(',', datastr);
            if (tok1 <= 0) then
               currentToken := datastr
            else
               begin
                currentToken := Trim(LeftStr(datastr, tok1 - 1));
                datastr := Trim(RightStr(datastr, Length(datastr) - tok1));
               end;

            // Tokenize token
            tok2 := Pos(':', currentToken);
            if (tok2 > 0) then
               begin
                tokenName := Trim(LeftStr(currentToken, tok2 - 1));
                tokenValue := Trim(RightStr(currentToken, Length(currentToken) - tok2));

                // Process tokenized token
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
                         tok3 := Pos(':', tokenValue);
                         if (tok3 > 0) then
                            begin
                             tokenName := Trim(LeftStr(tokenValue, tok3 - 1)); // Faction name
                             tokenValue := Trim(RightStr(tokenValue, Length(tokenValue) - tok3));
                             if TryStrToFloat(tokenValue, f, settings.FormatSettings) then
                                begin
                                 SetLength(gamedata.NearestStations, Length(gamedata.NearestStations) + 1);
                                 h := High(gamedata.NearestStations);
                                 gamedata.NearestStations[h].Owner := tokenName;
                                 gamedata.NearestStations[h].Distance := f / 1000.0; // To get the distance in km
                                end
                             else
                                Log(Format('[READ DATA]: Faction ''%s'' station distance (meters) ''%s'' is not a valid integer or float!', [tokenName, tokenValue]));
                            end
                         else
                            Log(Format('[READ DATA]: Faction station distance definition ''%s'' is invalid! Missing name/value separator '':''!', [tokenValue]));
                       end;
                     else
                       Log(Format('[READ DATA]: Unknown gameplay property ''%s''!', [tokenName]));
                end;
               end
            else
               Log(Format('[READ DATA]: Invalid gameplay property ''%s''! Missing name/value separator '':''!', [currentToken]));
          until (tok1 <= 0);

          // Zero mem (data used up)
          ZeroMemory(data, datalen);
         end

      // Token: request (EXE must send data to LUA script)
      else if AnsiStartsText(rqRequestData, datastr) then
         begin
          SendProgramData(data);
          gamedata.CurrentControlToken := 2; // Ct: Send Data (nothing to do afterwards!)
         end

      // Token: replay MP3
      else if AnsiStartsText(rqReplayTrack, datastr) then
         begin
          // Is heartbeat signal? Yes!
          Result := true;

          // Only change MP3, if we're on the MP3 station!
          h := High(stations);
          if (gamedata.GameStatus.CurrentStationIndex = h) and (stations[h].Handler.IsMP3Station) then
             gamedata.CurrentControlToken := 3; // Ct: Replay MP3

          // Zero mem (data used up)
          ZeroMemory(data, datalen);
         end

      // Token: Skip to next MP3
      else if AnsiStartsText(rqNextTrack, datastr) then
         begin
          // Is heartbeat signal? Yes!
          Result := true;

          // Only change MP3, if we're on the MP3 station!
          h := High(stations);
          if (gamedata.GameStatus.CurrentStationIndex = h) and (stations[h].Handler.IsMP3Station) then
             gamedata.CurrentControlToken := 4; // Ct: Next MP3

          // Zero mem (data used up)
          ZeroMemory(data, datalen);
         end

      // Token: Invalid
      else if not AnsiStartsText(rqProgramData, datastr) then
         begin
          Log(Format('[READ DATA]: Unknown data structure ''%s''!', [datastr]));

          // Zero mem (data used up)
          ZeroMemory(data, datalen);
         end;
     end;

  // Clean up
  UnmapViewOfFile(data);
  datastr := '';
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

procedure InitProgram;

          function internal_ReadString(name, def: string): string;
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

          function internal_ReadInt(name: string; def: integer): integer;
          var
            i: integer;
            s: string;
          begin
            s := internal_ReadString(name, '??');
            if TryStrToInt(s, i) then
               Result := i
            else
               Result := def;
          end;

          function internal_ReadFloat(name: string; def: double): double;
          var
            f: double;
            s: string;
          begin
            s := internal_ReadString(name, '??');
            if TryStrToFloat(s, f, settings.FormatSettings) then
               Result := f
            else
               Result := def;
          end;

var
  i, j, tok: integer;
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
  programdata.MaxLatency := min(5000, max(10, internal_ReadInt('Global.Latency', 1000)));
  // Loudness
  programdata.MasterLoudness := min(1.0, max(0.0, internal_ReadFloat('Global.LoudnessFactor', 1.0)));
  // Randomize tracks?
  programdata.RandomizeTracks := (internal_ReadInt('Global.RandomizeTracks', 0) <> 0);
  // No online streams?
  programdata.NoOnlineStreams := (internal_ReadInt('Global.NoOnlineStreams', 0) <> 0);;

  // Linearize volume?
  u_utils.bLinearizeVolume := (internal_ReadInt('Global.UseLinearVolume', 0) <> 0);

  // No of stations
  j := max(0, internal_ReadInt('Global.NumberOfStations', 0));

  // Radio stations data
  for i := 0 to j - 1 do
      begin
        filename := internal_ReadString(Format('Radio_%d.FileName', [i + 1]), '');
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
                       RsName := internal_ReadString(Format('Radio_%d.RadioText', [i + 1]), '?Unnamed Station?');
                       SetLength(Owners, 0);
                       // Multi-Owner system!
                       token := internal_ReadString(Format('Radio_%d.Owner', [i + 1]), '');
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
                       LoudnessFactor := min(1.0, max(0.0, internal_ReadFloat(Format('Radio_%d.LoudnessFactor', [i + 1]), 0.0)));
                       DampeningFactor := min(1.0, max(0.0, internal_ReadFloat(Format('Radio_%d.DampeningFactor', [i + 1]), 1.0)));
                       Handler := radio;
                     end;
               end
            else
               radio.Free;
            radio := nil;
           end;
      end;
  // MP3 station data
  if (internal_ReadInt('Radio_MP3.Enabled', 0) <> 0) then
     begin
      mp3list := TStringList.Create;
      GetMP3Data(mp3list);
      if (mp3list.Count > 0) then
         begin
          radio := TRadioStation.Create(mp3list, true);
          if radio.Valid then
             begin
              radio.WriteMP3Report('MP3Report.txt');
              SetLength(stations, Length(stations) + 1);
              with stations[High(stations)] do
                   begin
                     RsName := internal_ReadString('Radio_MP3.RadioText', '?Unnamed MP3 Station?');
                     SetLength(Owners, 0);
                     LoudnessFactor := min(1.0, max(0.0, internal_ReadFloat('Radio_MP3.LoudnessFactor', 0.0)));
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

procedure RunProgram;
var
  i: integer;
  paused: boolean = false;
  lasttick: int64 = 0;
begin
  // Pre-Init
  for i := 0 to High(stations) do
      begin
        stations[i].Handler.SetVolume(0.0);
        if programdata.RandomizeTracks then
           stations[i].Handler.RandomizePosition;
      end;
  // Loop
  while IsGameRunning do
        begin
          // Read data from the game
          if ReadGameData then
             case gamedata.CurrentControlToken of
                   // Apply game data (structure is already populated)
                   1: begin
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

                   // Replay MP3 (circumstances are already checked for)
                   3: if not paused then
                         stations[High(stations)].Handler.Replay;

                   // Skip MP3 (circumstances are already checked for)
                   4: if not paused then
                         stations[High(stations)].Handler.SkipNextTrack;
             end

          // No data for now...
          else if (not paused) and ((GetTickCount64 - lasttick) > programdata.MaxLatency) then
             begin
              paused := true;
              for i := 0 to High(stations) do
                  stations[i].Handler.SetPaused(true)
             end;

          // Progress station handlers
          for i := 0 to High(stations) do
              stations[i].Handler.DoProgress;

          // Wait, don't consume too much CPU!
          Sleep(programdata.MaxLatency div 4);
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

{$R *.res}

begin
  {Must set working dir to real current dir!}
  GetModuleFileName(GetModuleHandle(nil), argv[0], 32767);
  SetCurrentDir(ExtractFilePath(ParamStr(0)));
  {Music player, set priority to Above normal!}
  SetPriorityClass(GetCurrentProcess, $8000);
  {OK}
  randomize;
  mutex := OpenMutex(MUTEX_ALL_ACCESS, BOOL(0), PChar(mtxApplication));
  if (mutex = 0) then
     begin
       mutex := CreateMutex(nil, BOOL(0), PChar(mtxApplication));
       if not IsGameRunning then
          MessageBox(0, 'X4: Foundations is not running!', PChar(nameAppName), MB_OK + MB_ICONERROR)
       else
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
          end;
       ReleaseMutex(mutex);
     end
  else
     MessageBox(0, 'This application must have a single instance only!', PChar(nameAppName), MB_OK + MB_ICONERROR);
end.

