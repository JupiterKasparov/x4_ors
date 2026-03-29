unit u_oldconvert;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, StrUtils, LCLType, fpjson, u_jsonmanager;

function ConvertOldSettings(fileName: string): TJSONObject;

implementation

function IsNetFile(fn: string): boolean;
begin
  fn := Trim(fn);
  if (Pos('://', fn) > 0) then
     exit(true);
  exit(false);
end;

function ConvertOldSettings(fileName: string): TJSONObject;
var
  filePath, sectionName, orderByFileName, line: string;
  ini: TINIFile;
  stationCount, slotCount, i, j: integer;
  disableOnlineTracks, isMP3, isOrdered: boolean;
  arr, slots, slotOrderList: TJSONArray;
  rs, slot: TJSONObject;
  f: System.Text;
begin
  filePath := ExtractFilePath(fileName);
  Result := nil;
  ini := nil;
  try
    try
      Result := TJSONObject.Create;
      ini := TIniFile.Create(fileName, [ifoFormatSettingsActive]);
      ini.FormatSettings := DefaultFormatSettings;
      ini.FormatSettings.DecimalSeparator := '.';

      // Global settings
      sectionName := 'Global';
      stationCount := ini.ReadInteger(sectionName, 'NumberOfStations', 0);
      disableOnlineTracks := ini.ReadInteger(sectionName, 'NoOnlineStreams', 0) <> 0;
      SetIntegerSetting(Result, 'global.maxLatency', ini.ReadInteger(sectionName, 'Latency', 500));
      SetBooleanSetting(Result, 'global.randomizeTracks', ini.ReadInteger(sectionName, 'RandomizeTracks', 1) <> 0);
      SetBooleanSetting(Result, 'global.linearVolumeScale', ini.ReadInteger(sectionName, 'UseLinearVolume', 0) <> 0);
      SetFloatSetting(Result, 'global.masterLoudness', ini.ReadFloat(sectionName, 'LoudnessFactor', 1.0));
      SetStringSetting(Result, 'global._os_', '_is_windows_');

      // Key bindings
      sectionName := 'Keys';
      arr := SetListSetting(Result, 'global.keyBindings');
      arr.Add(ini.ReadInteger(sectionName, 'Modifier_1', 0));
      arr.Add(ini.ReadInteger(sectionName, 'Modifier_2', 0));
      arr.Add(ini.ReadInteger(sectionName, 'Func_PrevStation', 0));
      arr.Add(ini.ReadInteger(sectionName, 'Func_NextStation', 0));
      arr.Add(ini.ReadInteger(sectionName, 'Func_ReplayThisMP3', 0));
      arr.Add(ini.ReadInteger(sectionName, 'Func_SkipThisMP3', 0));
      arr.Add(ini.ReadInteger(sectionName, 'Func_ReloadApp', 0));

      // Radio stations
      arr := TJSONArray.Create;
      Result.Arrays['radioStations'] := arr;
      for i := 1 to stationCount do
          begin
            sectionName := Format('Radio_%d', [i]);
            rs := TJSONObject.Create;
            if (slotCount <= 0) then
               rs.Floats['masterLoudness'] := ini.ReadFloat(sectionName, 'LoudnessFactor', 1.0)
            else
               rs.Floats['masterLoudness'] := ini.ReadFloat(sectionName, 'MasterLoudnessFactor', 1.0);
            rs.Strings['name'] := ini.ReadString(sectionName, 'RadioText', '???');
            rs.Booleans['enabled'] := (not IsNetFile(ini.ReadString(sectionName, 'FileName', ''))) or (not disableOnlineTracks);

            // Radio station slots
            slotCount := ini.ReadInteger(sectionName, 'SlotCount', 0);
            slots := TJSONArray.Create;
            if (slotCount <= 0) then
               begin
                 isMP3 := ini.ReadInteger(sectionName, 'IsMP3', 0) <> 0;
                 isOrdered := ini.ReadInteger(sectionName, 'Ordered', 0) <> 0;
                 slot := TJSONObject.Create;
                 slot.Floats['loudness'] := 1.0;
                 slot.Floats['dampFactor'] := ini.ReadFloat(sectionName, 'DampeningFactor', 1.0);
                 slot.Strings['owners'] := ini.ReadString(sectionName, 'Owner', '');
                 slot.Booleans['isMP3Player'] := isMP3;
                 slot.Strings['url'] := ini.ReadString(sectionName, 'FileName', '');
                 slot.Booleans['isOrdered'] := isOrdered;
                 if isOrdered then
                    begin
                      slotOrderList := TJSONArray.Create;
                      orderByFileName := filePath + Format('radio_%d_order.lst', [i]);
                      System.Assign(f, orderByFileName);
                      {$I-}
                      Reset(f);
                      while not EOF(f) do
                            begin
                              readln(f, line);
                              line := Trim(line);
                              if (line <> '') then
                                 slotOrderList.Add(line);
                            end;
                      System.Close(f);
                      {$I+}
                      if (IOResult = 0) then
                         slot.Arrays['orderByList'] := slotOrderList
                      else
                         slotOrderList.Free;
                    end;
                 slots.Add(slot);
               end
            else
               begin
                 for j := 1 to slotCount do
                     begin
                       isMP3 := ini.ReadInteger(sectionName, Format('SlotIsMP3_%d', [j]), 0) <> 0;
                       isOrdered := ini.ReadInteger(sectionName, Format('SlotOrdered_%d', [j]), 0) <> 0;
                       slot := TJSONObject.Create;
                       slot.Floats['loudness'] := ini.ReadFloat(sectionName, Format('SlotLoudnessFactor_%d', [j]), 0.0);
                       slot.Floats['dampFactor'] := ini.ReadFloat(sectionName, Format('SlotDampeningFactor_%d', [j]), 0.0);
                       slot.Strings['owners'] := ini.ReadString(sectionName, Format('SlotOwner_%d', [j]), '');
                       slot.Booleans['isMP3Player'] := isMP3;
                       slot.Strings['url'] := ini.ReadString(sectionName, Format('SlotFileName_%d', [j]), '');
                       slot.Booleans['isOrdered'] := isOrdered;
                       if isOrdered then
                          begin
                            slotOrderList := TJSONArray.Create;
                            orderByFileName := filePath + Format('radio_%d_slot_%d_order.lst', [i, j]);
                            System.Assign(f, orderByFileName);
                            {$I-}
                            Reset(f);
                            while not EOF(f) do
                                  begin
                                    readln(f, line);
                                    line := Trim(line);
                                    if (line <> '') then
                                       slotOrderList.Add(line);
                                  end;
                            System.Close(f);
                            {$I+}
                            if (IOResult <> 0) then
                               slot.Arrays['orderByList'] := slotOrderList
                            else
                               slotOrderList.Free;
                          end;
                       slots.Add(slot);
                     end;
               end;
            // OK
            rs.Arrays['slots'] := slots;
            arr.Add(rs);
          end;

      // MP3 Player dedicated
      sectionName := 'Radio_MP3';
      rs := TJSONObject.Create;
      rs.Floats['masterLoudness'] := ini.ReadFloat(sectionName, 'LoudnessFactor', 1.0);
      rs.Strings['name'] := ini.ReadString(sectionName, 'RadioText', '? (MP3) ?');
      rs.Booleans['enabled'] := ini.ReadInteger(sectionName, 'Enabled', 0) <> 0;
      slots := TJSONArray.Create;
      slot := TJSONObject.Create;
      slot.Floats['loudness'] := 1.0;
      slot.Floats['dampFactor'] := 1.0;
      slot.Strings['owners'] := '';
      slot.Booleans['isMP3Player'] := true;
      slot.Strings['url'] := 'mp3';
      slot.Booleans['isOrdered'] := false;
      slots.Add(slot);
      rs.Arrays['slots'] := slots;
      arr.Add(rs);
    except
      if (Result <> nil) then
         Result.Free;
      exit(nil);
    end;
  finally
    if (ini <> nil) then
       ini.Free;
  end;
end;

end.

